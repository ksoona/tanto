Attack Vector Linux
===================
-the resurrection-

Context: When I attempted Attack Vector Linux 5 years ago, it was by adding Tails-esque featurs to Kali.
This time around, I intend to try to add Kali packages to Tails, which is doing it the other way around.

I think this approach is better because it is more of a privacy-first, secure-by-default architecture.
Note: This distro, like Tails, is designed as a live-linux. For dedicated install, I suggest Qubes-OS.

Phase Zero: Research
====================

I downloaded the latest ISO for each and extracted them. Then diffed the file live/filesystem.packages
Both Tails and Kali are based on Debian. Furthermore, the live versions are both based on Debian Live.

Documentation:
--------------
[Tails - Building a Tails image](https://tails.boum.org/contribute/build/)
[Tails - customize](https://tails.boum.org/contribute/customize/)
[DebianLive Wiki](https://wiki.debian.org/DebianLive/)
[Live Systems Manual](https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html) *The God Doc*
[Live Build a Custom Kali ISO](https://docs.kali.org/development/live-build-a-custom-kali-iso)
[Building Custom Kali Live ISO Images](https://kali.training/topic/building-custom-kali-live-iso-images/)
[Building Kali on Non-Kali Debian Based Systems](https://www.kali.org/tutorials/build-kali-with-live-build-on-debian-based-systems/)

Tails suggests building on Debian 9 (Stretch), or newer. Likewise, Kali can be build on Debian. We have now chosen our build system.

Phase One: Setup
================
(0) Install Debian 9
	`su -`
	`apt install sudo`
	Optional: `sudo apt install netselect-apt` (for getting your fastest local apt mirror)
(1) Install Tails build requirements:
	`sudo apt install psmisc git rake libvirt-daemon-system dnsmasq-base ebtables qemu-system-x86 qemu-utils vagrant vagrant-libvirt vmdebootstrap`
	`sudo systemctl restart libvirtd`
	```
	#!/bin/bash for group in kvm libvirt libvirt-qemu ; do
		sudo adduser "$(whoami)" "$group"
	done
	```
(2) Obtain Tails source code: 
	`git clone https://git-tails.immerda.ch/tails`
	`cd tails`
	`git checkout devel`
	`git submodule update --init`
(3) Notes on building Tails:
	`rake build && rake vm:halt`
	`rake build --trace && rake vm:halt` for verbose
	`rake clean_all` to clean the build environment after a failed build (not totally necessary if the build fails)
	if it failes a few times just clean and try again (build takes as long as the 1st time after clean) (which is hours)

	Vanilla Tails build debug issue #1:
	fails to patch Tor Browser AppArmor profile
	torbrowser-AppArmor-profile.patch

	Possible solution: get updated file from Whonix
	https://github.com/Whonix/apparmor-profile-torbrowser

	LOL I tracked down the issue on the Tails bug tracker and it got patched 6 days ago I just needed to do a `git pull`
	In the meantime I also leanred what "FTBFS" and "LGTM" stand for.

Phase Two: MAJIC
================
(?) Make modifications... Everything can be found on the God Doc:
https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-package-installation.en.html#463

OK, I so can add the Kali repository in a Tails build directory: `tails/config/chroot_sources`
Just create a file named `kali.chroot` with contents `deb http://http.kali.org/kali kali-rolling main non-free contrib`
(Also create a symbolic link to kali.binary as such: `ln -s kali.chroot kali.binary`)
Also got the GPG key from extracting this deb as follows: 
`wget http://http.kali.org/pool/main/k/kali-archive-keyring/kali-archive-keyring_2018.1_all.deb`
`dpkg-deb -R kali-archive-keyring_2018.1_all.deb tmp`
`cp tmp/usr/share/keyrings/kali-archive-keyring.gpg tails/config/chroot_sources/`
Then rename it and make symbolic link:
`cd tails/config/chroot_sources`
`mv kali-archive-keyring.gpg kali.chroot.gpg`
`ln -s kali.chroot.gpg kali.binary.gpg`
You should now be done with working in the `chroot_sources` directory.

https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-package-installation.en.html#397
Then I will have to list what packages to install here: `tails/config/chroot_local-packageslists`
A simple attempt is just to copy the same list from Kali's variant-gnome live-build scripts:
`wget https://raw.githubusercontent.com/prateepb/kali-live-build/master/kali-config/variant-gnome/package-lists/kali.list.chroot`
`mv kali.list.chroot kali-gnome.list`
So there are two package lists now.

Side note: The goal will be merging the packages lists. A cool grapical diff tool for this is called meld: `sudo apt install meld`
As an exercise I ran meld (just graphical diff) on the package lists of the extracted ISOs for Kali & Tails, but this wasn't necessary for development.

OK anyway trying to build at this point fails. Here is part of the error output:
```
The following packages have unmet dependencies:
 fdisk : Depends: libfdisk1 (>= 2.32) but 2.29.2-1+deb9u1 is to be installed
 libpam-systemd : Depends: systemd (= 237-3~bpo9+1) but it is not going to be installed
 perl-modules-5.26 : Depends: perl-base (>= 5.26.2-1) but 5.24.1-3+deb9u4 is to be installed
                     Breaks: perl (< 5.26.2~) but 5.24.1-3+deb9u4 is to be installed
                     Recommends: perl (>= 5.26.2-1) but 5.24.1-3+deb9u4 is to be installed
 reportbug-gtk : Depends: reportbug (= 7.5.0) but 7.1.7+deb9u2 is to be installed
E: Unable to correct problems, you have held broken packages.
```
As you can see there are package version mismatches. It could be that Kali uses packages from Debian unstable and Tails from stable or something like that.
A possible solution is to use apt pinning: https://wiki.debian.org/AptPreferences and the relevant file in the Tails build is `config/chroot_apt/preferences`
See also: article including apt-pinning in Kali: https://www.kali.org/tutorials/advanced-package-management-in-kali-linux/

I tried adding these lines to `config/chroot_apt/preferences`:
```
Package: *
Pin: release o=Kali,n=kali-rolling
Pin-Priority: 990
```
Now we have different errors. I take this as a good sign. I think I will keep this change.
```
The following packages have unmet dependencies:
 tails-iuk : Depends: tails-perl5lib (>= 2.0) but it is not going to be installed
 tails-persistence-setup : Depends: libfunction-parameters-perl (>= 2.001003) but it is not going to be installed
                           Depends: tails-perl5lib (>= 2.0) but it is not going to be installed
 xserver-xorg-video-all : Depends: xserver-xorg-video-ati but it is not going to be installed
                          Depends: xserver-xorg-video-fbdev but it is not going to be installed
                          Depends: xserver-xorg-video-nouveau but it is not going to be installed
                          Depends: xserver-xorg-video-vesa but it is not going to be installed
                          Depends: xserver-xorg-video-vmware but it is not going to be installed
 xserver-xorg-video-amdgpu : Depends: xorg-video-abi-24
 xserver-xorg-video-cirrus : Depends: xorg-video-abi-24
 xserver-xorg-video-intel : Depends: xorg-video-abi-24
 xserver-xorg-video-qxl : Depends: xorg-video-abi-24
E: Unable to correct problems, you have held broken packages.
```
So, I wrote an additional file `tanto-extras.list` in `tails/config/chroot_local-packageslists`:
```
# v0.2 Build Fixes
tails-perl5lib
libfunction-parameters-perl
xserver-xorg-video-ati
xserver-xorg-video-fbdev
xserver-xorg-video-nouveau
xserver-xorg-video-vesa
xserver-xorg-video-vmware
xserver-xorg-core
xorg-video-abi-24

# a e s t h e t i c s
gnome-shell-extension-system-monitor
```
Closer...
```
Package xorg-video-abi-24 is a virtual package provided by:
  xserver-xorg-core 2:1.20.1-4 [Not candidate version]
  xserver-xorg-core 2:1.20.1-1 [Not candidate version]

E: Package 'xorg-video-abi-24' has no installation candidate
```
OK just replace the latter string with the former and try again.
Fail. Complains about lack of package `xorg-video-abi-24`
Adding it back in gets us back to the error above. Hmm.
I Googled for the errant package and it is only in Debian sid. Maybe I can pin this package:
```
Package: xorg-video-abi-24 xserver-xorg-core xserver-common libfunction-parameters-perl
Pin: release o=Debian,n=sid
Pin-Priority: 999
```
Method described above, same file `tails/config/chroot_apt/preferences`. I later found out that `libfunction-parameters-perl` is pinned to stretch-backports earlier in the file. Whoops.
Well it turns out that package is a Virtual Package so I read the documentation on those.
Maybe just try pinning the package it is provided by too. I just listed it in the same line.
Next failure: `E: Unable to locate package perlapi` Solution: remove from package list.
```
The following packages have unmet dependencies:
 libfunction-parameters-perl : Depends: perlapi-5.24.1
 virtualbox-guest-x11 : Depends: xorg-video-abi-23
 xserver-xorg-core : Depends: xserver-common (>= 2:1.20.1-4) but 2:1.19.2-1+deb9u2 is to be installed
E: Unable to correct problems, you have held broken packages.
```
`apt search perlapi` returns `libperl-apireference-perl` so I added that to the package list.
Also added `xorg-video-abi-23` and `xserver-common` whilst pinning these two latter packages.

ALMOST THERE
				STAY ON TARGET
ALMOST THERE
```
Package xorg-video-abi-23 is a virtual package provided by:
  xserver-xorg-core 2:1.19.2-1+deb9u2 [Not candidate version]

E: Package 'xorg-video-abi-23' has no installation candidate
```
Last time, with `xorg-video-abi-24`, I resolved the issue by pinning the package.
I'm currently pinning both to the same release, and I should probably double check that.
Well damn it looks like this one is in sid too and I ought to be able to pin it. Hmm.
Oh fuck I think I see what is happening. Both of these want a different version of
`xserver-xorg-core`. I suppose one is being requested by Tails and one by Kali.
I will try to resolve this to the newer version.

Yes indeed it seems this is the case. Tails is requesting package `virtualbox-guest-x11`
which is in the file `config/chroot_local-packageslists/tails-common.list` and it is this
package that is dependent on the older version of `xorg-video-abi-23` and `xserver-xorg-core`

Let's see if `virtualbox-guest-x11` is pinned or not, maybe we can pin it to sid too.
Huh well it is definitely pinned so this could definitely break things.
There's a current entry in `config/chroot_local-apt/preferences`:
```
Package: virtualbox*
Pin: release o=Debian,n=stretch-backports
Pin-Priority: 999
```
I don't fully understand backports yet, so it seems like changing this to sid will break things.
But let's try it anyway. Well holy Shit it kinda worked. Now we are back to the `perlapi` problem
```
The following packages have unmet dependencies:
 libfunction-parameters-perl : Depends: perlapi-5.24.1
E: Unable to correct problems, you have held broken packages.
```
So obviously adding `libperl-apireference-perl` did not fix that, and I can remove it.
`apt search libfunction-parameters-perl` returns no results on my Debian 9 stable. Hrm..
Google search for `libfunction-parameters-perl` results in this definitely being in sid.
				LET'S PIN IT
Huh however `perlapi` is only in Stretch. Maybe I should pin it too.
Actually I don't need to pin `libfunction-paremeters-perl`, just `perlapi`.
```
Package: perlapi perl-base perl
Pin: release o=Debian,n=stretch
Pin-Priority:999
```
Same error. Fuck maybe not backports just stretch. Trying again. Note I deleted these lines later
No dice. Maybe I need it in a package list.
`E: Unable to locate package perlapi`
Well what now. Maybe do try `stretch-backports` but with it in the packageslist now.
Same problem again.
https://packages.debian.org/stretch/perlapi-5.24.1
Mother Fucker! Another virtual package.
Again I will pin both the virtual and the providing package, in this case, `perl-base`
OK maybe these aren't in `stretch-backports` after all. Switching back to `stretch`.
The new error:
```
The following packages have unmet dependencies:
 perl : Depends: perl-base (= 5.26.2-7) but 5.24.1-3+deb9u4 is to be installed
 perl-modules-5.26 : Depends: perl-base (>= 5.26.2-1) but 5.24.1-3+deb9u4 is to be installed
E: Unable to correct problems, you have held broken packages.
```
Ah, a clear version mismatch. What I would like to do is not include `libgtk-pixbuf2.0` since the UI is going to be based mostly on Kali anyway, which is the old package that requries old perl, or I can try rolling back all of the perl. Since I've already started walking down this path, I'm going to roll back (by pinning) all of the perl. Let's see where this goes!
Well, I'm dumb, I can't do that, `perl-modules-5.26` clearly requires 5.26 so I can't pin back to 5.24 obviously.
So fuck it let's figure out what bullshit is using this outdated GTK package and get it the fuck out.
`cat config/chroot_local-packageslists/*.list | grep pixbuf` gets you `gtk2-engines-pixbuf` and checking out that package with `apt show` demonistrates that it's literally a theme engine. Bye.
Commented it out of `tails-common.list` and then removed the pin for the perl packages.
Fingers crossed.
Nope. Damn. It still tries to pull in `libgdk-pixbuf2.0` so commenting out that line wasn't good enough. Gotta find what is trying to pull that in. Huh looks like the package is in both stretch and sid, so maybe I can pin it to sid and it won't try to pull in perlapi from stretch.
```
Package: libgdk-pixbuf2.0-0
Pin: release o=Debian,n=sid
Pin-Priority: 999
```
It's getting late, I'm an idiot, that's not the package I need to pin at all. Deleted lines
The one that required `perlapi` in the first place is `libfunction-parameters-perl`
So let's cut it out and see if that helps anything toward a working build.
`libfunction-parameters-perl` is required by `tails-persistence-setup`
So I can either remove `tails-persistence-setup` or maybe pin `libfunction-parameters-perl` to a newer version, let me try the latter first. Looks like its in sid, let's do it.
```
Package: libfunction-parameters-perl
Pin: release o=Debian,n=sid
Pin-Priority: 999
```
(Or you can just append to the line with Xorg and shit.)

HOLY COW IT IS PAST THE PACKAGES PART AND NOW FAILS WHILE PATCHING
```
P: Applying patch config/chroot_local-patches/Desktop-Notify:_0001-support_notification_actions.patch...
patching file usr/share/perl5/Desktop/Notify.pm
Reversed (or previously applied) patch detected!  Assume -R? [n] 
Apply anyway? [n] 
Skipping patch.
3 out of 3 hunks ignored -- saving rejects to file usr/share/perl5/Desktop/Notify.pm.rej
patching file usr/share/perl5/Desktop/Notify/Notification.pm
Hunk #1 FAILED at 59.
Hunk #2 FAILED at 81.
Hunk #3 succeeded at 144 with fuzz 2 (offset 19 lines).
Hunk #4 FAILED at 154.
3 out of 4 hunks FAILED -- saving rejects to file usr/share/perl5/Desktop/Notify/Notification.pm.rej
P: Begin unmounting filesystems...
```
So the file its patching is part of a package called `libdesktop-notify-perl` but researching it this is not the issue, pinning `libfunction-parameters-perl` from `stretch-backports` to `sid` is what causes the break, the version number goes from... anyway, just see below:
I got on Tails' IRC channel so I could scream my debugging woes into a void:
```
10:50:13   ksoona | so I had to pin package libfunction-parameters-perl to sid for my branch to get pack package build dependencies, but this breaks the first "Desktop-Notify" patch             │
10:53:11   ksoona | I heard there was some targeting buster and was curious if anyone is working on an updated patch or wants to pair on it. this could be an intrigeri question as they wrote    │
                  | the original patch                                                                                                                                                            │
10:53:51   ksoona | also I should probably get on Jabber but bleh                                                                                                                                 │
10:56:21   ksoona | although now that I look more closely at the patch: intrigeri's code works fine, it fails at a part contributed by Stephen Cavilia, C                                         │
10:56:49   ksoona | anyway any devs want to pair with me debugging this? I'll wait.                                                                                                               │
11:05:04   ksoona | huh it looks like /usr/share/perl5/Desktop/Notify/Notification.pm is the file in package libdesktop-notify-perl that gets patched, but I'm not pinning that package I don't   │
                  | think and there haven't been any major changes to the package either I don't think                                                                                            │
11:07:00   ksoona | oh fuck I have two pinning entries for `libdesktop-notify-perl` let me try to deconflict them                                                                                 │
11:08:39   ksoona | yeah so the sid one has a higher priority so I assume it's taking precedence, there must be a delta between sid and stretch-backports gonna dig a lil further                 │
11:10:45   ksoona | oh wait they had the same priority. huh. wonder how apt preferences parses that, it must have gone with the latest entry since adding it fixed a build bug I had earlier      │
11:22:30   ksoona | OK yeah there is a delta for `libfunction-parameters-perl` from `stretch-backports` to `sid`, version number changes from 2.001003-1 in the current working tails build to    │
                  | 2.001003-2 in my branch. I had to upgrade perl to satisfy another dependency
```
I think most of the core devs use Jabber these days anyway. I mean XMPP. You know what I mean.


NEGATIVE
NEGATIVE
				IT DIDN'T GO IN
			IMPACTED ON THE SURFACE

Let's regroup. Desktop notification seems like a "bells-and-whistles" feature, I wonder if I can comment out this patch and see where the next fail is. I tried commenting out every line past 66
Huh it still errors out, I wonder if I rename the .patch file to .patch.backup or something

Nope gotta rm it.

Rinse.
Repeat.

Here's all the patches I had to delete:
```
ken@esper:~/code/tanto/config/chroot_local-patches$ diff ../../../tails/config/chroot_local-patches/ .
Only in ../../../tails/config/chroot_local-patches/: apparmor-adjust-cupsd-profile.diff
Only in ../../../tails/config/chroot_local-patches/: apparmor-adjust-gst_plugin_scanner-profile.diff
Only in ../../../tails/config/chroot_local-patches/: apparmor-adjust-python-abstraction.diff
Only in ../../../tails/config/chroot_local-patches/: apparmor-adjust-totem-profile.diff
Only in ../../../tails/config/chroot_local-patches/: apparmor-aliases.diff
Only in ../../../tails/config/chroot_local-patches/: cupsd-IPv4_only.patch
Only in ../../../tails/config/chroot_local-patches/: Desktop-Notify:_0001-support_notification_actions.patch
Only in ../../../tails/config/chroot_local-patches/: Desktop-Notify:_0002-support_hints.patch
Only in ../../../tails/config/chroot_local-patches/: live-boot:_dont_mount_live_overlay_twice.patch
```

After removing a number of patches that didn't take, now the build fails at the first hook.
I'm tempted to take the same dirty approach, simply removing any script that errors out.
We'll see what happens. This probably breaks a lot of Tails functionality and features.
I'll accept this tradeoff in order to get Kali tools.

Here's everything I removed:
```
ken@esper:~/code/tanto/config/chroot_local-hooks$ diff ../../../tails/config/chroot_local-hooks/ .
Only in ../../../tails/config/chroot_local-hooks/: 01-check-for-dot-orig-files
Only in ../../../tails/config/chroot_local-hooks/: 04-change-gids-and-uids
Only in ../../../tails/config/chroot_local-hooks/: 05-adduser_tails-persistence-setup
```
Damn had to remove a hook that helps with `tails-persistence-setup` will have to fix that l8r
```
Setting up onionshare (1.3-1) ...
Killed
P: Begin unmounting filesystems...
```
We are past the hooks and now fail installing onionshare. I'll comment this from packageslists.
And blast, we have our first Kali package failure:
```
Setting up dradis (3.10.0-0kali1) ...
Adding system user `dradis' (UID 128) ...
Adding new group `dradis' (GID 137) ...
Adding new user `dradis' (UID 128) with group `dradis' ...
Creating home directory `/var/lib/dradis' ...
Killed
P: Begin unmounting filesystems...
```
There are also a number of notable UID errors, probably from removing that Tails hook.
This one isn't called out specifically in packageslists because it's part of the kali-linux-full metapackage.
Just for the sake of getting this to build so I can submit it to a CFP, let's cut out hundreds of Kali tools and use only the kali-linux-top10 metapackage just as a test.
Fails on hook #44 now, removing it.
`44-remove-unused-AppArmor-profiles`
Oh lol one of the hooks is just a symbolic link to an earlier one that I removed I guess tails build needed it to run twice gotta remove the symlink now.
```
E: config/chroot_local-hooks/99-zzz_check_uids_and_gids failed (exit non-zero). You should check for errors.
P: Begin unmounting filesystems...
```
I should have seen that coming.

Once I removed the reproducible build postprocessing script everything went to shit.
Trying a `rake clean_all` and then `rake build --trace`
I think I'm fucked
```
P: Begin ensuring chroot contents are reproducible...
P: Deconfiguring file /etc/kernel-img.conf
P: Deconfiguring file /etc/apt/sources.list
P: Deconfiguring file /etc/apt/apt.conf
P: Deconfiguring file /etc/hostname
P: Deconfiguring file /bin/hostname
P: Deconfiguring file /etc/resolv.conf
P: Deconfiguring file /etc/hosts
P: Deconfiguring file /usr/sbin/policy-rc.d
P: Deconfiguring file /usr/sbin/initctl
P: Deconfiguring file /sbin/start-stop-daemon
P: Deconfiguring file /etc/debian_chroot
P: Begin unmounting /sys...
P: Begin unmounting /selinux...
P: Begin unmounting /proc...
P: Begin unmounting /dev/pts...
P: Begin caching chroot stage...
P: Begin unmounting filesystems...
P: Setting up cleanup function
P: Begin copying chroot...
P: This may take a while.
rake aborted!
```



N.B. `cd config` then `tree` is really useful for analyzing how Tails is structured and built.

(~) For comparison the Kali build script: https://github.com/prateepb/kali-live-build/blob/master/build.sh



Phase Three: a e s t h e t i c s
================================
https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-contents.en.html#517
Finally I will want to run some scripts to setup the GUI how I like it and configure some installed tools:
I can modify some of my `rice` scripts and put them in `tails/config/chroot_local-hooks`

Graphic design and branding: `tails/data/splash.png` what else?
I wrote a get-wallpaper script in the rice repo for my other user, and thats the background I want to use.
Wallaper files are in `config/chroot_local-includes/usr/share/tails`