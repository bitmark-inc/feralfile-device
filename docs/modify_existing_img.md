Guide to Modify Raspberry Pi OS Image from AWS Instance

This guide provides detailed steps to modify a Raspberry Pi OS image on an AWS instance, including connecting via SSH and preparing the modified image for deployment.

1. Connect to the AWS Instance

	1.	Open a terminal on your local machine.
	2.	SSH into the AWS instance:

ssh admin@ec2-98-83-221-82.compute-1.amazonaws.com


	3.	If you’re using a private key for authentication (e.g., my-key.pem), use:

ssh -i <ask_anh_for_key> admin@ec2-98-83-221-82.compute-1.amazonaws.com

2. Install Required Tools

	1.	Update the package repository:

sudo apt update
sudo apt upgrade -y


	2.	Install necessary tools:

sudo apt install wget xz-utils qemu-user-static kpartx e2fsprogs fdisk dosfstools util-linux parted unzip

3. Download the Raspberry Pi OS Image

	1.	Navigate to the working directory:

mkdir ~/raspbian-modify
cd ~/raspbian-modify


	2.	Download the Raspberry Pi OS image:

wget https://downloads.raspberrypi.com/raspios_arm64/images/raspios_arm64-2024-11-19/2024-11-19-raspios-bookworm-arm64.img.xz


	3.	Extract the image:

xz -d 2024-11-19-raspios-bookworm-arm64.img.xz

4. Mount and Access the Image

	1.	Attach the image to a loop device:

sudo losetup -Pf 2024-11-19-raspios-bookworm-arm64.img.xz


	2.	Verify the loop device:

sudo losetup -l

Example output:

/dev/loop0       3.0G  0 loop  /home/admin/raspbian-modify/2024-11-19-raspios-bookworm-arm64.img.xz


	3.	Map the partitions:

sudo kpartx -av /dev/loop0


	4.	Mount the partitions:

sudo mkdir -p /mnt/raspbian/boot /mnt/raspbian/root
sudo mount /dev/mapper/loop0p1 /mnt/raspbian/boot
sudo mount /dev/mapper/loop0p2 /mnt/raspbian/root

5. Chroot into the Image

	1.	Copy QEMU binary to enable ARM emulation:

sudo cp /usr/bin/qemu-arm-static /mnt/raspbian/root/usr/bin/


	2.	Bind required directories:

sudo mount --bind /dev /mnt/raspbian/root/dev
sudo mount --bind /proc /mnt/raspbian/root/proc
sudo mount --bind /sys /mnt/raspbian/root/sys
sudo mount --bind /run /mnt/raspbian/root/run


	3.	Enter the chroot environment:

sudo chroot /mnt/raspbian/root

6. Modify the Image

6.1 Create a Predefined User

	1.	Add the user feralfile:

adduser feralfile --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password


	2.	Set the password:

echo 'feralfile:feralfile' | chpasswd


	3.	Add the user to the sudo group:

usermod -aG sudo feralfile



6.2 Configure Auto-Login

	1.	Create the auto-login configuration:

mkdir -p /etc/systemd/system/getty@tty1.service.d
nano /etc/systemd/system/getty@tty1.service.d/autologin.conf


	2.	Add the following content:

[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin feralfile --noclear %I $TERM


	3.	Save and exit.

6.3 Set Keyboard Layout to US

Edit the keyboard configuration:

nano /etc/default/keyboard

Replace the contents with:

XKBMODEL="pc104"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"

6.4 Install and Configure Chromium Kiosk Mode

	1.	Install Chromium:

apt update
apt install -y chromium-browser


	2.	Create autostart configuration:

mkdir -p /home/feralfile/.config/autostart
nano /home/feralfile/.config/autostart/chromium-kiosk.desktop


	3.	Add the following:

[Desktop Entry]
Type=Application
Name=Chromium Kiosk
Exec=chromium-browser --kiosk --start-fullscreen --no-extensions https://display.feralfile.com
X-GNOME-Autostart-enabled=true


	4.	Set permissions:

chown -R feralfile:feralfile /home/feralfile/.config

7. Exit and Clean Up

	1.	Exit chroot:

exit


	2.	Unmount and detach loop devices:

sudo umount /mnt/raspbian/root/dev
sudo umount /mnt/raspbian/root/proc
sudo umount /mnt/raspbian/root/sys
sudo umount /mnt/raspbian/root/run
sudo umount /mnt/raspbian/boot
sudo umount /mnt/raspbian/root
sudo kpartx -dv /dev/loop0
sudo losetup -d /dev/loop0

8. Compress the Modified Image

	1.	Compress the image:

zip -r raspbian-modified.zip 2024-11-19-raspios-bookworm-arm64.img.xz


	2.	Share the compressed image with the team.

9. Flash the Image Using BalenaEtcher

	1.	Download BalenaEtcher: https://etcher.io/
	2.	Select the downloaded .zip file.
	3.	Choose the target SD card.
	4.	Click Flash!

10. First Boot Instructions

	1.	Attach a keyboard and mouse.
	2.	If no network connection is available:
	•	Press Alt + F4 to exit kiosk mode.
	•	Use the GUI to configure Wi-Fi or connect Ethernet.
	•	Reboot to relaunch kiosk mode:

sudo reboot

Default Credentials

	•	Username: feralfile
	•	Password: feralfile