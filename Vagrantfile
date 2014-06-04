VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.box = "centos6.5dev"
  config.vm.network "forwarded_port", guest: 8080, host: 8080
  config.vm.provision :shell, :inline => <<-EOT
yum update -y
yum groupinstall -y 'Development Tools'
yum install -y docker-io
gpasswd -a vagrant docker
chkconfig docker on
service docker start
EOT
  config.vm.provision :reload
end

