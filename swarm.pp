# Sets up consul + docker swarm
# Consul manager server ips are set using environment variable $host_ips; a comma-separated list of consul hosts 

$consul_ver     = '0.6.3'
if $host_ip == undef { $host_ip = $::ipaddress }
notify {"Swarm adverising on ip:${host_ip}":}

if size($::consul_servers) < 1 {
  notify { "Unable to get the list of consul ip's - Variable \'\$host_ips\' is undef. This string variable of comma-separated ip's is used by consul to join nodes using the \'start_join\' parameter).": } 
} else {
  $consul_server_ips = split($::consul_servers, ',')
}

notify {"Consul servers are: ${consul_server_ips}.":}

package { 'unzip': ensure => installed }

if "${::consul_role}" == "server"  {  
  notify {"Configuring this host as a consul server":}
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
  notify {"Configuring this host as a consul node with swarm":}
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
      'start_join'       => [ "${consul_server_ips[0]}" ],
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
    command => "join --addr=${host_ip}:2375 consul://${consul_server_ips[0]}:8500/swarm_nodes",
  }
  
  ::docker::run { 'swarm-manager':
    image   => 'swarm',
    ports   => '4000:4000',
    command => "manage -H :4000 --replication --advertise ${host_ip}:4000 consul://${consul_server_ips[0]}:8500/swarm_nodes",
    require => [
      Docker::Run['swarm'],
      Class['::consul'],
    ],
  }
}
