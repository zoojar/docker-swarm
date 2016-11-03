
$consul_ver = '0.6.3'
$host_ip        = $::ipaddress
$host_interface = "eth1"
notify {"Swarm adverising on interface: ${host_interface}, ip:${host_ip}":}
notify {"Consul Role=${::consul_role}. Swarm Role=${::swarm_role}.":}
notify {"Consul Server IP: ${::consul_server_ip}.":}

package { 'unzip': ensure => installed }

if "${host_ip}" == "${consul_server_ip}" {
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
      'advertise_addr'   => "${::consul_server_ip}",
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
      'start_join'       => ["${::consul_server_ip}"],
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
  image => 'swarm',
  ports => '3000:2375',
  command => "manage --replication --advertise ${host_ip}:3000 consul://${host_ip}:8500/swarm_nodes",
  require => [
    Docker::Run['swarm'],
    Class['::consul'],
  ],
}