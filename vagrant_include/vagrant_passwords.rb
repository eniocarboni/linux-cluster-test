# **
# Linux-cluster-test
# Copyright (c) 2020 Enio Carboni (enio.carboni __at__ gmail.com)
# Distributed under the GNU GPL v3. For full terms see the file LICENSE.
# **
# Description: Simulate a linux N node cluster with cps, Pacemaker and Corosync in Centos 7 ior Ubuntu 1804 lts vms
#    This is an include file of the main Vagrantfile
# **

# CHARS: chars for randomize user password
$CHARS = ('0'..'9').to_a + ('A'..'Z').to_a + ('a'..'z').to_a + ('#'..'&').to_a + (':'..'?').to_a
# random_password method: return a 12 (or length) random characters for user password
def random_password(length=12)
  p=''
  (0..length).each do
    p+=$CHARS[rand($CHARS.size)]
  end
  return p
end
Dir.mkdir("vagrant_pwd") unless File.exists?("vagrant_pwd")
if $ALWAYS_CHANGE_ALL_PASSWORD
  File.delete("vagrant_pwd/.hacluster_pwd") if File.exist?("vagrant_pwd/.hacluster_pwd")
  File.delete("vagrant_pwd/.fencecluster_pwd") if File.exist?("vagrant_pwd/.fencecluster_pwd")
  File.delete("vagrant_pwd/.vagrant_pwd") if File.exist?("vagrant_pwd/.vagrant_pwd")
end
# hacluster_pwd: password of hacluster user
if File.file?("vagrant_pwd/.hacluster_pwd")
  $hacluster_pwd=File.read("vagrant_pwd/.hacluster_pwd")
else
  $hacluster_pwd=random_password
  File.write("vagrant_pwd/.hacluster_pwd",$hacluster_pwd)
  puts "Create new hacluster_pwd in vagrant_pwd/.hacluster_pwd file: #{$hacluster_pwd}"
end
if $FENCE_AGENT
  # fencecluster_pwd: password of fence user
  if File.file?("vagrant_pwd/.fencecluster_pwd")
    $fencecluster_pwd=File.read("vagrant_pwd/.fencecluster_pwd")
  else
    $fencecluster_pwd=random_password
    File.write("vagrant_pwd/.fencecluster_pwd",$fencecluster_pwd)
    puts "Create new fencecluster_pwd in vagrant_pwd/.fencecluster_pwd file: #{$fencecluster_pwd}"
  end
end
if $SECURE_VAGRANT_USER_PWD
  # vagrant_user_pwd: password of vagrant user
  if File.file?("vagrant_pwd/.vagrant_pwd")
    $vagrant_user_pwd=File.read("vagrant_pwd/.vagrant_pwd")
  else
    $vagrant_user_pwd=random_password
    File.write("vagrant_pwd/.vagrant_pwd",$vagrant_user_pwd)
    puts "Create new vagrant_user_pwd in vagrant_pwd/.vagrant_pwd file: #{$vagrant_user_pwd}"
  end
end
