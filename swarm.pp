# Sets up consul + docker swarm
# Consul manager server ips are set using environment variable $host_ips; a comma-separated list of consul hosts 

$consul_ver     = '0.6.3'
$host_ip        = $::ipaddress
$host_interface = "eth1"
notify {"Swarm adverising on interface: ${host_interface}, ip:${host_ip}":}

if $::host_ips == "" {
  fail("Unable to determine consul host ips using environment variable \$host_ips: ${::host_ips}"")
} else {
  $consul_server_ips = split($::host_ips, ',')
}

notify {"Consul Server IP's: ${consul_server_ips}.":}

package { 'unzip': ensure => installed }

if size($consul_server_ips) <= 1  {  
  #(If i am the only node here then declare myself as a server)
  class { '::consul':
    require     => Package['unzip'],
    version     => $consul_ver,
    config_hash => {
      'server'           => true,
      'datacenter'       => 'dc1',
      'data_dir'         => '/opt/consul',
      'ui_dir'           => '/opt/consul/ui',
      'client_addr'      => '0.0.0.0',
      'bind_addr'        => "${host_ip}",
      'node_name'        => "$::hostname",
      'advertise_addr'   => "${host_ip}",
      'bootstrap_expect' => '1',
    }
  }
} else { 
  class { '::consul':
    require     => Package['unzip'],
    version     => $consul_ver,
    config_hash => {
      'bootstrap'        => false,
      'server'           => false,
      'datacenter'       => 'dc1',
      'data_dir'         => '/opt/consul',
      'ui_dir'           => '/opt/consul/ui',
      'client_addr'      => '0.0.0.0',
      'bind_addr'        => "${host_ip}",
      'node_name'        => "$::hostname",
      'start_join'       => $consul_server_ips,
    }
  }
}

consul::service { 'docker-service':
  checks  => [
    {
      script   => 'service docker status',
      interval => '10s',
      tags     => ['docker-service']
    }
  ],
  address => "${host_ip}",
}

class { '::docker':
  tcp_bind => 'tcp://0.0.0.0:2375',
}

::docker::run { 'swarm':
  require => Class['::consul'],
  image   => 'swarm',
  command => "join --addr=${host_ip}:2375 consul://${host_ip}:8500/swarm_nodes",
}

::docker::run { 'swarm-manager':
  image   => 'swarm',
  ports   => '3000:2375',
  command => "manage --replication --advertise ${host_ip}:3000 consul://${host_ip}:8500/swarm_nodes",
  require => [
    Docker::Run['swarm'],
    Class['::consul'],
  ],
}