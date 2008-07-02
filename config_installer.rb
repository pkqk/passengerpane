#!/usr/bin/env ruby

require 'osx/cocoa'
require 'yaml'
require 'fileutils'

class String
  def bypass_safe_level_1
    str = dup
    str.untaint
    str
  end
end

class ConfigInstaller
  attr_reader :data
  
  def initialize(yaml_data, extra_command = nil)
    @data = YAML.load(yaml_data)
    @extra_command = extra_command
  end
  
  def add_to_hosts(index)
    host = @data[index]['host']
    OSX::NSLog("Will add host: #{host}")
    system "/usr/bin/dscl localhost -create /Local/Default/Hosts/#{host.bypass_safe_level_1} IPAddress 127.0.0.1"
  end
  
  VHOSTS_DIR = "/private/etc/apache2/passenger_pane_vhosts"
  def verify_vhost_conf
    unless File.exist? VHOSTS_DIR
      OSX::NSLog("Will create directory: #{VHOSTS_DIR}")
      FileUtils.mkdir_p VHOSTS_DIR
    end
  end
  
  CONF = "/private/etc/apache2/other/passenger_pane.conf"
  def verify_httpd_conf
    unless File.exists?(CONF)
      OSX::NSLog("Will try to write passenger pane vhosts conf to: #{CONF}")
      File.open(CONF, 'a') do |f|
        f.write(<<APACHECONF)
# Added by the Passenger preference pane
LoadModule passenger_module /Library/Ruby/Gems/1.8/gems/passenger-2.0.1/ext/apache2/mod_passenger.so
<IfModule passenger_module>
  PassengerRoot /Library/Ruby/Gems/1.8/gems/passenger-2.0.1
  PassengerRuby /System/Library/Frameworks/Ruby.framework/Versions/1.8/usr/bin/ruby

  NameVirtualHost *:80
  Include /private/etc/apache2/passenger_pane_vhosts/*.conf
</IfModule>
APACHECONF
      end
    end
  end
  
  def create_vhost_conf(index)
    app = @data[index]
    public_dir = File.join(app['path'], 'public')
    vhost = %{
<VirtualHost #{app['vhostname']}>
  ServerName #{app['host']}
  DocumentRoot "#{public_dir}"
  RailsEnv #{app['environment']}
  RailsAllowModRewrite #{app['allow_mod_rewrite'] ? 'on' : 'off'}
#{ "#{app['user_defined_data']}\n" unless app['user_defined_data'].empty? }</VirtualHost>
}.sub(/^\n/, '')
    
    OSX::NSLog("Will write vhost file: #{app['config_path']}\nData: #{vhost}")
    File.open(app['config_path'].bypass_safe_level_1, 'w') { |f| f << vhost }
  end
  
  def restart_apache!
    system "sudo /bin/launchctl stop org.apache.httpd"
  end
  
  def install!
    verify_vhost_conf
    verify_httpd_conf
    
    (0..(@data.length - 1)).each do |index|
      add_to_hosts index
      create_vhost_conf index
    end
    
    restart_apache!
  end
end

if $0 == __FILE__
  OSX::NSLog("Will try to write config(s).")
  ConfigInstaller.new(*ARGV).install!
end