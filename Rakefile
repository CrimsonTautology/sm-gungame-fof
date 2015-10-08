require 'rake'
require 'fileutils'
require 'socket'
 
SOURCEMOD = ENV["SOURCEMOD_DIR"]
SERVER    = ENV["SOURCEMOD_DEV_SERVER"]
PASSWORD  = ENV["SOURCEMOD_DEV_SERVER_PASSWORD"]
 
SPCOMP    = ENV["SPCOMP"] || File.join(SOURCEMOD, "scripting/spcomp")
 
PROJECT_ROOT = Dir.pwd
SCRIPTING    = 'addons/sourcemod/scripting/'
PLUGINS      = 'addons/sourcemod/plugins/'
EXTENSIONS   = 'addons/sourcemod/extensions/'
TRANSLATIONS = 'addons/sourcemod/translations/'
CONFIGS      = 'addons/sourcemod/configs/'
 
task :default => [:compile, :install, :reload]
 
desc "Compile project"
task :compile do
  fail 'Enviornment variable "SPCOMP" not set' unless SPCOMP

  Dir.chdir File.join(PROJECT_ROOT, SCRIPTING)
  Dir.glob('*.sp') do |f|
    smxfile = f.gsub(/\.sp$/, ".smx")
    puts %x{#{SPCOMP} #{f}  -i"$PWD/include" -o"../plugins/#{smxfile}" -w203 -w204}
    #puts %x{#{SPCOMP} #{f}  -i"$PWD/include" -o"../plugins/#{smxfile}"}
    puts "compile #{f}"
  end
end
 
 
desc "Copy compiled project to development server"
task :install do
  #Install smx files
  install_filetype '*.smx', PLUGINS

  #Install translations
  install_filetype '*.phrases.txt', TRANSLATIONS

  #Install extensions if they don't exist
  install_filetype '*.so', EXTENSIONS, false

  #Install data configfiles
  install_filetype '*.txt', CONFIGS, false
end
 
desc "Clean up compiled files"
task :clean do
  Dir.chdir File.join(PROJECT_ROOT, PLUGINS)
  Dir.glob('*.smx') do |f|
    FileUtils.rm(f)
    puts "clean #{f}"
  end
end

desc "Remove project from development server"
task :uninstall do
  fail 'Enviornment variable "SOURCEMOD_DEV_SERVER" not set' unless SERVER

  Dir.chdir File.join(PROJECT_ROOT, PLUGINS)
  Dir.glob('*.smx') do |f|
    FileUtils.rm(File.join(SERVER, PLUGINS, f))
    puts "uninstall #{f}"
  end
end
 
desc "Reload sourcemod on development server"
task :reload do
  rcon_session do |server|
    puts server.rcon_exec('say [SRCDS] Reloading sourcemod')
    puts server.rcon_exec('sm plugins unload_all')
    puts server.rcon_exec('sm plugins refresh')
    puts server.rcon_exec('say [SRCDS] Reload completed')
  end
end
 
desc "Send an RCON command to the development server (rake rcon['sv_cheats 1'])"
task :rcon, [:cmd] do |t, args|
  rcon_session do |server|
    puts server.rcon_exec("#{args.cmd}")
  end
end
 
desc "Update project's version number (e.g. rake version[1.2.3])"
task :version, [:ver] do |t, args|
  puts "hit version"
  Dir.chdir File.join(PROJECT_ROOT, SCRIPTING)
  Dir.glob('*.sp') do |f|
    content = File.read(f)
    content.gsub!(/#define PLUGIN_VERSION "[^"]*"/, %Q{#define PLUGIN_VERSION "#{args.ver}"})

      File.open(f, "w") {|file| file.puts content}
    puts "bump #{f} to version #{args.ver}"
  end

end

def rcon_session
  require 'steam-condenser'
  fail 'Enviornment variable "SOURCEMOD_DEV_SERVER_PASSWORD" not set' unless PASSWORD

  local_ip = Socket::getaddrinfo(Socket.gethostname,"echo",Socket::AF_INET)[0][3]
  server = SourceServer.new(local_ip)
  begin
    server.rcon_auth(PASSWORD)

    yield(server)
  rescue RCONNoAuthError
    warn 'Could not authenticate with the game server.'
  rescue Errno::ECONNREFUSED
    warn "Server not found"
  end
end

def install_filetype glob, subdirectory, overwrite=true
  fail 'Enviornment variable "SOURCEMOD_DEV_SERVER" not set' unless SERVER
  return unless File.directory?(File.join(PROJECT_ROOT, subdirectory))

  Dir.chdir File.join(PROJECT_ROOT, subdirectory)
  Dir.glob(glob) do |f|
    path = File.join(SERVER, subdirectory, f)
    disabled = File.join(SERVER, subdirectory, "disabled", f)
    next if FileTest.exists?(disabled)

    if overwrite || !FileTest.exists?(path)
      FileUtils.mkdir_p(File.dirname(path))
      FileUtils.cp(f, path)
      puts "install #{f}"
    end
  end
end
