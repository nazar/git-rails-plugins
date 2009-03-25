#!/usr/bin/ruby

# ruby module to manage rails plugins in an git-svn dcommit friendly way
#
# Copyright 2008 Nazar Aziz - nazar@panthersoftware.com
# Modified 2009 Andrew Carter <ascarter@gmail.com>

require 'optparse'
require 'ostruct'
require 'fileutils'
require 'fileutils'
require 'yaml'

# Override default /usr/bin paths by setting environment vars
GIT_PATH = ENV['GIT_RAILS_PLUGINS_GIT_PATH'] || '/usr/bin'
SVN_PATH = ENV['GIT_RAILS_PLUGINS_SVN_PATH'] || '/usr/bin'

options = OpenStruct.new

#parse command line
opt = OptionParser.new do |opts|
  #defaults
  options.op     = ''
  options.plugin = ''
  options.svn    = ''
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
  
  opts.on("-s", "--svn EXTERN_PATH", "Clone all referenced svn:externals plugins at EXTERN_PATH") do |v|
    options.op = 'svn'
    options.svn = v
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
  
  attr_accessor :name, :remote_head, :remote_author, :remote_date, :remote_commit_log, :remote_path, :type, 
                :plugin_head, :plugin_author, :plugin_date, :plugin_commit_log, :plugin_path
  
  GIT_CMD     = File.join(GIT_PATH, 'git')
  GIT_LOG_CMD = "`#{GIT_CMD} log -n1`"
  
  #constructors
  
  def initialize(name, vendor)
    @name        = name.strip
    @plugin_path = File.join(vendor.path, @name)
    @remote_path = ''
    @type        = -1 # -1 - not initialised, 1 - clone, 2 - svn external ref
  end
  
  #class methods
  
  def self.clone_git_repo(git_path, vendor)
    plugin = Plugin.new(File.basename(git_path), vendor)
    plugin.remote_path = git_path
    plugin.type = 1 #git clone
    #valid GIT repository?
    raise "#{git_path} is not a GIT reposiroty" unless plugin.valid_git_repository(git_path)
    #query log and get last commit
    plugin.load_from_remote_last_commit_info
    #load plugin info
    plugin.load_from_local_plugin_info
    #
    return plugin
  end
  
  def self.clone_svn_external(name, svn_path, vendor)
    plugin = Plugin.new(name, vendor)
    plugin.remote_path = svn_path.strip
    plugin.type = 2 #svn:externals clone
    #
    return plugin
  end
  
  #instance methods
  
  #determine if: un-initialised, upto date or requires commit/rebase/pull
  def status
    #does the plugin exist?
    if File.directory?(File.join(@plugin_path, '.git'))
      #okay...exists.. compare hashes
      if type == 1
        @remote_hash != @plugin_head ? 1 : 2
      else
        3
      end
    else  
      0
    end
  end
  
  def status_description
    case status
      when 0; 'un-initialised'
      when 1; 'needs update'
      when 2; 'up-to-date'
      when 3; 'svn clone - cannot determine status (yet..)'
    end
  end 
  
  def update
    puts "Processing #{name}"
    #does the plugin exist?
    if File.directory?(File.join(@plugin_path, '.git'))
      pull
    else
      clone
    end
    load_from_local_plugin_info
    puts ""
  end
  
  def clone
    unless File.exist?(@plugin_path)
      puts "cloning #{name}"
      #cloning git or svn repository?
      case type
      when 1 #GIT repos
        puts eval("`#{GIT_CMD} clone #{@remote_path} #{@plugin_path}`")
      when 2 #svn:externals 
        puts eval("`#{GIT_CMD} svn clone #{@remote_path} #{@plugin_path}`")
      end
    else
      puts "Directory exists in #{@plugin_path}. Skipping clone. Pulling instead"
      pull
    end
    #read cloned info
    load_from_local_plugin_info
    puts ""
  end
  
  def pull
    puts "pulling #{name}"
    git_action do
      puts eval("`#{GIT_CMD} checkout master`")
      #pull from git or svn?
      case type
      when 1
        puts eval("`#{GIT_CMD} pull`")
      when 2
        #cmd = "`#{GIT_CMD} svn rebase`"; puts Dir.pwd
        puts eval("`#{GIT_CMD} svn rebase`")
      end
      #update plugin vars
      load_from_local_plugin_info
    end
  end
  
  def push
    puts "pushing #{name} to #{remote_path}"
    git_action do
      #git or svn?
      case type
      when 1
        puts eval("`#{GIT_CMD} push`")
        load_from_remote_last_commit_info
      when 2
        puts eval("`#{GIT_CMD} svn dcommit`")
      end
      #update plugin vars
      load_from_local_plugin_info
    end
    puts ""
  end
  
  def execute(command)
    puts "executing '#{command}' on #{plugin_path}"
    git_action do
      puts eval("`#{command}`")
      #update plugin vars
      load_from_local_plugin_info
      load_from_remote_last_commit_info if type == 1
    end
    puts ""
  end
  
    #does a shallow check by just looking for a .git directory in the given path
  def valid_git_repository(path)
    raise "#{path} is not a directory" unless File.directory?(path)                                                                
    raise "#{path} is not a git repository" unless File.exist?(File.join(path,'.git')) && (File.directory?(File.join(path,'.git')))
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

  def git_action &block
    #cd to plugin directory...change to master and pull
    pwd = Dir.pwd
    begin
      FileUtils.cd(@plugin_path)
      block.call
    ensure
      FileUtils.cd(pwd)      
    end
  end
end

#Plugins class encapsulates Rails plugins by enumerating all plugins and providing per plugin methods
class Plugins
  SVN_CMD = File.join(SVN_PATH, 'svn')
  
  attr_accessor :path, :plugins
  
  #constructor
  
  def initialize
    @path = File.join(Dir.pwd,'vendor','plugins')
    #this script can only be called from rails_root
    raise "Script was run from #{Dir.pwd}. Please run it from your Rails root directory" unless File.directory?(@path)
    #
    @plugins_file = File.join(Dir.pwd, '.plugins')
    if File.exist?(@plugins_file)
      @plugins = File.open( @plugins_file  ) { |yf| YAML::load( yf ) }
    else
      @plugins = {}
    end
  end
  
  #class methods

  def self.add(git_path)
    vendor = Plugins.new
    git_path.each do |plugin_path|
      plugin = Plugin.clone_git_repo(plugin_path, vendor)
      vendor.add_plugin(plugin)
    end
    #finally... save to .plugins
    vendor.save
  end
  
  #expects a valid SVN path that contains an svn:externals property. Parse property and git-svn clone all referenced plugins
  def self.clone_svn_externals(svn_extern_prop)
    vendor = Plugins.new
    props = eval("`#{SVN_CMD} propget svn:externals #{svn_extern_prop}`")
    #error check
    raise "Error: #{props}" if props[/does not exist/]
    raise "No svn:externals found at #{svn_extern_prop}" unless props.split('\n').length > 0
    #do it
    props.each_line do |external|
      match = /(.+)\s+(.+)/.match(external)
      if match
        raise "un-expected svn externals format #{external}" unless match.length == 3
        plugin = Plugin.clone_svn_external(match[1], match[2], vendor)
        plugin.clone
        vendor.add_plugin(plugin)
      else
        puts 'No matches... skipping'
      end
      vendor.save
    end
  end
  
  def self.list
    self.iterate_over_plugins{|plugin| puts "#{plugin.name} - #{plugin.status_description} - #{plugin.plugin_head}"}
  end

  def self.update(plugins)
    self.iterate_over_plugins(plugins){|plugin| plugin.update}
  end

  def self.push(plugins)
    self.iterate_over_plugins(plugins){|plugin| plugin.push}
  end
  
  def self.command(command, plugins)
    self.iterate_over_plugins(plugins){|plugin| plugin.execute(command)}
  end
  
  def self.iterate_over_plugins(plugins = [])
    plugins = [] unless plugins
    vendor = Plugins.new
    if vendor.plugins.length > 0
      vendor.plugins.each do |p_name, p_plugin|
        yield p_plugin if (plugins.length == 0) || (plugins.include?(p_name))
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
    @plugins[name] = value
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
  
  def add_plugin(plugin)
    if @plugins[plugin.name]
      puts "Plugin #{plugin.name} updated"
    else
      puts "Plugin #{plugin.name} added"
    end
    @plugins[plugin.name] = plugin
  end
  
end


################# main ##################

case options.op
  when 'add';     Plugins.add(options.plugin)
  when 'list';    Plugins.list
  when 'update';  Plugins.update(options.plugin)
  when 'push';    Plugins.push(options.plugin)
  when 'command'; Plugins.command(options.command, options.plugin)
  when 'svn';     Plugins.clone_svn_externals(options.svn)
end
