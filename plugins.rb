#!/usr/bin/ruby

require 'optparse'
require 'ostruct'
require 'fileutils'
require 'ftools'
require 'fileutils'
require 'yaml'


GIT_PATH = '/usr/bin/'

options = OpenStruct.new

#parse command line
opt = OptionParser.new do |opts|
  #defaults
  options.op = ''
  options.plugin = ''
  #
  opts.banner = "Usage: plugins [options]"
  opts.separator ""
  opts.separator "Specific options:"  

  opts.on("-a", "--add PLUGIN", "Add Plugin (expects local GIT repository. Command Seperated for multiple") do |v|
    options.op = 'add'
    options.plugin = v
  end
  
  opts.on("-l", "--list", "List Plugins") do |v|
    options.op = 'list'
  end

  opts.on("-u", "--update [PLUGIN]", "update a plugin. If no plugin listed then update all plugins. Plugins can be comma seperated.") do |v|
    options.op = 'update'
    options.plugin = v
  end

  opts.on("-p", "--push [PLUGIN]", "push a plugin. If no plugin listed then push all plugins. Plugins can be comma seperated.") do |v|
    options.op = 'push'
    options.plugin = v
  end
  
  opts.on("-c", "--command [PLUGIN]:\"COMMAND\"", "Execute command. Comma seperate if more than one plugin") do |v|
    options.op = 'command'
    #can be wither of form :"git checkout master" or plugin1, plugin2, plugin3:"git checkout master"
    match = /(.+):(.+)|^:(.+)/.match(v)
    if match.length == 4
      if match[1]
        options.plugin = match[1]  
        options.command = match[2]
      else
        options.plugin = nil
        options.command = match[3]
      end
    else
      raise "#{v} un-recognised option parameter"
    end
  end
  
  opts.on_tail("-?", "--help", "Show this message") do
    puts opts
    exit
  end

end

opt.parse!

# tidy up command options
options.plugin = options.plugin.split(',') if options.plugin 

# check for valid op

if options.op == ''
  puts opt.to_s 
  exit
end

################# classes ##################

class Plugin
  
  attr_accessor :name, :remote_head, :remote_author, :remote_date, :remote_commit_log, :plugin_head, :plugin_author, :plugin_date, :plugin_commit_log, :plugin_path 
  
  GIT_CMD     = File.join(GIT_PATH, 'git')
  GIT_LOG_CMD = "`#{GIT_CMD} log -n1`"
  
  def initialize(git_path, vendor_path)
    @remote_path = File.expand_path(git_path)
    @name = File.basename(git_path)
    @plugin_path = File.join(vendor_path, @name)
    #valid GIT repository?
    raise "#{path} is not a GIT reposiroty" unless valid_git_repository
    #query log and get last commit
    load_from_remote_last_commit_info
    #load plugin info
    load_from_local_plugin_info
  end
  
  #instance methods
  
  #determine if: un-initialised, upto date or requires commit/rebase/pull
  def status
    #does the plugin exist?
    if File.directory?(File.join(@plugin_path, '.git'))
      #okay...exists.. compare hashes
      @remote_hash != @plugin_hash ? 1 : 2
    else  
      0
    end
  end
  
  def status_description
    case status
      when 0; 'un-initialised'
      when 1; 'needs update'
      when 2; 'up-to-date'
    end
  end 
  
  def update
    #does the plugin exist?
    if File.directory?(File.join(@plugin_path, '.git'))
      pull
    else
      clone
    end
  end
  
  def clone
    raise "non git dir exists in #{@plugin_path}. Delete first." if File.exist?(@plugin_path)
    puts eval("`#{GIT_CMD} clone #{@remote_path} #{@plugin_path}`")
    load_from_local_plugin_info
  end
  
  def pull
    #cd to plugin directory...change to master and pull
    pwd = Dir.pwd
    begin
      FileUtils.cd(@plugin_path)
      puts eval("`#{GIT_CMD} checkout master`")
      puts eval("`#{GIT_CMD} pull`")
      #update plugin vars
      load_from_local_plugin_info
    ensure
      FileUtils.cd(pwd)      
    end
  end
  
  def push
    #cd to plugin directory...change to master and pull
    pwd = Dir.pwd
    begin
      FileUtils.cd(@plugin_path)
      puts eval("`#{GIT_CMD} push`")
      #update plugin vars
      load_from_local_plugin_info
      load_from_remote_last_commit_info
    ensure
      FileUtils.cd(pwd)      
    end
  end
  
  def execute(command)
    #cd to plugin directory...change to master and pull
    pwd = Dir.pwd
    begin
      FileUtils.cd(@plugin_path)
      puts eval("`#{command}`")
      #update plugin vars
      load_from_local_plugin_info
      load_from_remote_last_commit_info
    ensure
      FileUtils.cd(pwd)      
    end
  end
  
  
  protected
  
  #does a shallow check by just looking for a .git directory in the given path
  def valid_git_repository
    raise "#{@remote_path} is not a directory" unless File.directory?(@remote_path)                                                                
    raise "#{@remote_path} is not a git repository" unless File.exist?(File.join(@remote_path,'.git')) && (File.directory?(File.join(@remote_path,'.git')))
    return true
  end

  #query the remote GIT repository for latest commit
  def load_from_remote_last_commit_info
    #need to change into remote dir then change back once done...always change back
    pwd = Dir.pwd
    begin
      FileUtils.cd(@remote_path)
      log = eval(GIT_LOG_CMD)
      #parse output
      match = /^commit\s+(.+)\nAuthor:\s+(.+)\nDate:\s+(.+)\n+\s+(.+)/.match(log)
      raise "Error in parsing log:\n#{log}" unless match && match.length > 0
      @remote_head       = match[1]
      @remote_author     = match[2]
      @remote_date       = match[3]
      @remote_commit_log = match[4]
    ensure
      FileUtils.cd(pwd)
    end
  end
  
  #query local plugin's git repo for its HEAD
  def load_from_local_plugin_info
    if File.exist?(@plugin_path)
      pwd = Dir.pwd
      begin
        FileUtils.cd(@plugin_path)
        log = eval(GIT_LOG_CMD)
        #parse output
        match = /^commit\s+(.+)\nAuthor:\s+(.+)\nDate:\s+(.+)\n+\s+(.+)/.match(log)
        raise "Error in parsing log:\n#{log}" unless match && match.length > 0
        @plugin_head       = match[1]
        @plugin_author     = match[2]
        @plugin_date       = match[3]
        @plugin_commit_log = match[4]
      ensure
        FileUtils.cd(pwd)      
      end    
    end
  end
  
end

#Plugin class encapsulates Rails plugins by enumerating all plugins and providing per plugin methods
class Plugins
  
  attr_accessor :path, :plugins
  
  #constructor
  
  def initialize
    @plugins = {}
    @path = File.join(Dir.pwd,'vendor','plugins')
    #this script can only be called from rails_root
    raise "Script was run from #{Dir.pwd}. Please run it from your Rails root directory" unless File.directory?(@path)
    #
    @plugins_file = File.join(Dir.pwd, '.plugins')
    @plugins = File.open( @plugins_file  ) { |yf| YAML::load( yf ) }
  end
  
  #class methods
  
  def self.add(git_path)
    vendor = Plugins.new
    git_path.each do |plugin_path|
      plugin = Plugin.new(plugin_path, vendor.path)
      #
      if vendor[plugin.name]
        puts "Plugin #{plugin.name} updated"
      else
        puts "Plugin #{plugin.name} added"
      end
      vendor[plugin.name] = plugin
    end
    #finally... save to .plugins
    vendor.save
  end
  
  def self.list
    vendor = Plugins.new
    if vendor.plugins.length > 0
      vendor.plugins.each do |p_name, p_plugin|
        puts "#{p_name} - #{p_plugin.status_description} - #{p_plugin.plugin_head}"
      end
    else
      puts "No plugins yet."
    end
  end
  
  def self.update(plugins = [])
    plugins = [] unless plugins
    vendor = Plugins.new
    if vendor.plugins.length > 0
      vendor.plugins.each do |p_name, p_plugin|
        p_plugin.update if (plugins.length == 0) || (plugins.include?(p_name))
      end
    else
      puts "No plugins yet."
    end
    #finally... save to .plugins
    vendor.save
  end

  def self.push(plugins = [])
    plugins = [] unless plugins
    vendor = Plugins.new
    if vendor.plugins.length > 0
      vendor.plugins.each do |p_name, p_plugin|
        p_plugin.push if (plugins.length == 0) || (plugins.include?(p_name))
      end
    else
      puts "No plugins yet."
    end
    #finally... save to .plugins
    vendor.save
  end
  
  def self.command(command, plugins = [])
    plugins = [] unless plugins
    vendor = Plugins.new
    puts command
    if vendor.plugins.length > 0
      vendor.plugins.each do |p_name, p_plugin|
        p_plugin.execute(command) if (plugins.length == 0) || (plugins.include?(p_name))
      end
    else
      puts "No plugins yet."
    end
    #finally... save to .plugins
    vendor.save
  end
  
  #instance methods
  
  def [] (plugin)
    @plugins[plugin]
  end
  
  def []= (name, value=nil)
    @plugins[name] = value if value
  end
  
  #constructs or updates .plugins file at RAILS root for tracking plugins
  def save
    File.open( @plugins_file, 'w' ) do |out|
      YAML.dump( @plugins, out )
    end
  end
  
  def dot_plugins_exists
    File.exist?(@plugins_file)
  end
  
  def length
    @plugins.length
  end
  
  private
  
  def enumerate_plugins
    dir = Dir.new(@path)
    #must have plugins in vendor/plugins
    raise "No plugins found in #{@path}" unless dir.entries.length > 0
    #enumerate all plugins and create
    @plugins = {}
    dir.each do |plugin|
      @plugins[plugin] = Plugin.new(@path << plugin) unless plugin[0,1] == '.'
    end
  end
  
end


################# main ##################

case options.op
  when 'add';     Plugins.add(options.plugin)
  when 'list';    Plugins.list
  when 'update';  Plugins.update(options.plugin)
  when 'push';    Plugins.push(options.plugin)
  when 'command'; Plugins.command(options.command, options.plugin)
end