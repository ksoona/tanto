def persistent_dirs
  ['/etc/ssh',
   '/home/amnesia/.claws-mail',
   '/home/amnesia/.gconf/system/networking/connections',
   '/home/amnesia/.gnome2/keyrings',
   '/home/amnesia/.gnupg',
   '/home/amnesia/.mozilla/firefox/bookmarks',
   '/home/amnesia/.purple',
   '/home/amnesia/.ssh',
   '/home/amnesia/Persistent',
   '/home/amnesia/custom_persistence',
   '/var/cache/apt/archives',
   '/var/lib/apt/lists']
end

Given /^I create a new (\d+) GiB USB drive named "([^"]+)"$/ do |size, name|
  next if @skip_steps_while_restoring_background
  @vm.create_new_usb_drive(name, size)
end

Given /^I clone USB drive "([^"]+)" to a new USB drive "([^"]+)"$/ do |from, to|
  next if @skip_steps_while_restoring_background
  @vm.clone_usb_drive(from, to)
end

Given /^I plug USB drive "([^"]+)"$/ do |name|
  next if @skip_steps_while_restoring_background
  @vm.plug_usb_drive(name)
  dev = @vm.usb_drive_dev(name)
  try_for(20) { @vm.execute("test -b #{dev}").success? }
end

Given /^I unplug USB drive "([^"]+)"$/ do |name|
  next if @skip_steps_while_restoring_background
  @vm.unplug_usb_drive(name)
end

def usb_install_helper(name)
  @screen.wait('USBCreateLiveUSB.png', 10)

  # FIXME: here we should select USB drive using #{name}
#  @screen.wait('USBTargetDevice.png', 10)
#  match = @screen.find('USBTargetDevice.png')
#  region_x = match.x
#  region_y = match.y + match.height
#  region_w = match.width*3
#  region_h = match.height*2
#  ocr = Sikuli::Region.new(region_x, region_y, region_w, region_h).text
#  STDERR.puts ocr
#  # Unfortunately this results in almost garbage, like "|]dev/sdm"
#  # when it should be /dev/sda1

  @screen.click('USBCreateLiveUSB.png')
#  @screen.hide_cursor
  @screen.wait('USBCreateLiveUSBNext.png', 10)
  @screen.click('USBCreateLiveUSBNext.png')
#  @screen.hide_cursor
  @screen.wait('USBInstallationComplete.png', 60*60)
  @screen.type(Sikuli::KEY_RETURN)
  @screen.type(Sikuli::KEY_F4, Sikuli::KEY_ALT)
end

When /^I "Clone & Install" Tails to USB drive "([^"]+)"$/ do |name|
  next if @skip_steps_while_restoring_background
  step "I run \"liveusb-creator-launcher\""
  @screen.wait('USBCloneAndInstall.png', 10)
  @screen.click('USBCloneAndInstall.png')
  usb_install_helper(name)
end

When /^I "Clone & Upgrade" Tails to USB drive "([^"]+)"$/ do |name|
  next if @skip_steps_while_restoring_background
  step "I run \"liveusb-creator-launcher\""
  @screen.wait('USBCloneAndUpgrade.png', 10)
  @screen.click('USBCloneAndUpgrade.png')
  usb_install_helper(name)
end

When /^I do a "Upgrade from ISO" on USB drive "([^"]+)"$/ do |name|
  next if @skip_steps_while_restoring_background
  step "I run \"liveusb-creator-launcher\""
  @screen.wait('USBUpgradeFromISO.png', 10)
  @screen.click('USBUpgradeFromISO.png')
  @screen.wait('USBUseLiveSystemISO.png', 10)
  match = @screen.find('USBUseLiveSystemISO.png')
  pos_x = match.x + match.width/2
  pos_y = match.y + match.height*2
  @screen.click(pos_x, pos_y)
  @screen.wait('USBSelectISO.png', 10)
  @screen.click('GnomeFileDiagTypeFilename.png')
  iso = "#{shared_dir_target}/#{File.basename(ENV['ISO'])}"
  @screen.type(iso + Sikuli::KEY_RETURN)
  usb_install_helper(name)
end

def shared_dir_target
  "/tmp/shared_dir"
end

Given /^I boot Tails from DVD with a Tails ISO image available$/ do
  next if @skip_steps_while_restoring_background
#  @vm.stop if @vm
#  @vm = VM.new
  new_tails_instance
  shared_dir_source = File.dirname(ENV['ISO'])
  tag = "iso_dir"
  @vm.add_share(shared_dir_source, tag)
  step "a freshly started Tails"
  @vm.execute("mkdir -p #{shared_dir_target}")
  @vm.execute("mount -t 9p -o trans=virtio #{tag} #{shared_dir_target}")
end

Given /^I enable all persistence presets$/ do
  next if @skip_steps_while_restoring_background
  @screen.wait('PersistenceWizardPresets.png', 20)
  # Mark first non-default persistence preset
  @screen.type("\t\t")
  # Check all non-default persistence presets
  10.times do
    @screen.type(" \t")
  end
  # Now we'll have the custom persistence field selected
  @screen.type('/home/amnesia/custom_persistence')
  @screen.type('a', Sikuli::KEY_ALT)
  @screen.type('/etc/ssh')
  @screen.type('a', Sikuli::KEY_ALT)
  @screen.click('PersistenceWizardSave.png')
  @screen.wait('PersistenceWizardDone.png', 20)
  @screen.type(Sikuli::KEY_F4, Sikuli::KEY_ALT)
end

Given /^I create a persistent partition with password "([^"]+)"$/ do |pwd|
  next if @skip_steps_while_restoring_background
  step "I run \"tails-persistence-setup\""
  @screen.wait('PersistenceWizardWindow.png', 20)
  @screen.wait('PersistenceWizardStart.png', 20)
  @screen.type(pwd + "\t" + pwd + Sikuli::KEY_RETURN)
  @screen.wait('PersistenceWizardPresets.png', 120)
  step "I enable all persistence presets"
end

Then /^a Tails persistence partition exists on USB drive "([^"]+)"$/ do |name|
  next if @skip_steps_while_restoring_background
  step "a freshly started Tails"
  dev = @vm.usb_drive_dev(name)
  data_partition_dev = dev + "2"
  info = @vm.execute("udisks --show-info #{data_partition_dev}").stdout
  info_split = info.split("\n  partition:\n")
  dev_info = info_split[0]
  part_info = info_split[1]
  assert dev_info.match("^  usage: +crypto$")
  assert dev_info.match("^  type: +crypto_LUKS$")
  assert part_info.match("^    scheme: +gpt$")
  assert part_info.match("^    label: +TailsData$")
end

Given /^I enable persistence with password "([^"]+)"$/ do |pwd|
  next if @skip_steps_while_restoring_background
  match = @screen.find('TailsGreeterPersistence.png')
  pos_x = match.x + match.width/2
  # height*2 may seem odd, but we want to click the button below the
  # match. This may even work accross different screen resolutions.
  pos_y = match.y + match.height*2
  @screen.click(pos_x, pos_y)
  @screen.wait('TailsGreeterPersistencePassphrase.png', 10)
  match = @screen.find('TailsGreeterPersistencePassphrase.png')
  pos_x = match.x + match.width*2
  pos_y = match.y + match.height/2
  @screen.click(pos_x, pos_y)
  @screen.type(pwd)
end

Given /^I enable read-only persistence with password "([^"]+)"$/ do |pwd|
  step "I enable persistence with password \"#{pwd}\""
  next if @skip_steps_while_restoring_background
  @screen.wait('TailsGreeterPersistenceReadOnly.png', 10)
  @screen.click('TailsGreeterPersistenceReadOnly.png')
end

Given /^persistence has been enabled$/ do
  next if @skip_steps_while_restoring_background
#  try_for(60) {
#    @vm.execute("mount").stdout.include? "_unlocked on "
#  }
  try_for(60) {
  mount = @vm.execute("mount").stdout
  persistent_dirs.each do |dir|
    if ! mount.include? "on #{dir} "
      raise "persistent dir #{dir} missing"
    end
  end
  }
end

When /^I boot Tails from USB drive "([^"]+)"$/ do |name|
  next if @skip_steps_while_restoring_background
#  @vm.stop if @vm
#  @vm = VM.new
  new_tails_instance
  @vm.set_usb_boot(name)
  step "a freshly started Tails"
end

Then /^Tails seems to have booted normally$/ do
  next if @skip_steps_while_restoring_background
  # FIXME: Something more we should check for?
  step "GNOME has started"
end

Then /^Tails is running from a USB drive$/ do
  next if @skip_steps_while_restoring_background
  # Approach borrowed from
  # config/chroot_local_includes/lib/live/config/998-permissions
  boot_dev_id = @vm.execute("udevadm info --device-id-of-file=/live/image").stdout
  boot_dev = @vm.execute("readlink -f /dev/block/'#{boot_dev_id}'").stdout
  boot_dev_info = @vm.execute("udevadm info --query=property --name='#{boot_dev}'").stdout
  boot_dev_type = (boot_dev_info.split("\n").select { |x| x.start_with? "ID_BUS=" })[0].split("=")[1]
  assert boot_dev_type == "usb"
end

When /^I write some files expected to persist$/ do
  next if @skip_steps_while_restoring_background
  persistent_dirs.each do |dir|
    owner = @vm.execute("stat -c %U #{dir}").stdout.strip
    assert @vm.execute("touch #{dir}/XXX_persist", user=owner).success?
  end
end

When /^I remove some files expected to persist$/ do
  next if @skip_steps_while_restoring_background
  persistent_dirs.each do |dir|
    assert @vm.execute("rm #{dir}/XXX_persist").success?
  end
end

When /^I write some files not expected to persist$/ do
  next if @skip_steps_while_restoring_background
  persistent_dirs.each do |dir|
    owner = @vm.execute("stat -c %U #{dir}").stdout.strip
    assert @vm.execute("touch #{dir}/XXX_gone", user=owner).success?
  end
end

Then /^only the expected files should persist on USB drive "([^"]+)"$/ do |name|
  next if @skip_steps_while_restoring_background
  step "I boot Tails from USB drive \"#{name}\""
  step "the network is unplugged"
  step "I enable persistence with password \"asdf\""
  step "I log in to a new session"
  step "persistence has been enabled"
  persistent_dirs.each do |dir|
    assert @vm.execute("test -e #{dir}/XXX_persist").success?
    assert ! @vm.execute("test -e #{dir}/XXX_gone").success?
  end
end
