# Sets up consul + docker swarm
# Consul manager server ips are set using environment variable $host_ips; a comma-separated list of consul hosts 

$consul_ver     = '0.6.3'
if $host_ip == undef { $host_ip = $::ipaddress }
notify {"Swarm adverising on ip:${host_ip}":}

if size($::host_ips) < 1 {
  fail("Unable to get the list of consul ip's - Variable \'\$host_ips\' is undef. This string variable of comma-separated ip's is used by consul to join nodes using the \'start_join\' parameter).")
} else {
  $consul_member_ips = split($::host_ips, ',')
}

notify {"Members of the Consul cluster: ${consul_member_ips}.":}

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
      'start_join'       => $consul_member_ips,
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