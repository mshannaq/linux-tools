# Working with sclaeway RPN-SAN and mount it in Dedibox running Rocky Linux

If you have RPN-SAN from scaleway and you want to mount it in your Linux server, you can follow the following steps to do that.

- Add your server to the RPN SAN Allowed IP list
- Make sure your server is configured for Local Area Network (LAN) access  and Access the RPN SAN via the correct Local LAN gateway
- Installing the required packages , iscsi-initiator-utils if you want to use iscsi devices
- Check RPN SAN devices
- Mount the iSCSI Device
- Automate Mounting on Boot (optional)

## Add your server to the RPN SAN Allowed IP list

First of all make sure to add your server to the RPN SAN Allowed IP list, see [How to connect a Dedibox to RPN SAN
](https://www.scaleway.com/en/docs/dedibox-network/rpn/how-to/connect-rpn-san/)

try to ping the RPN SAN IP address to make sure that you can access it. e.g: `ping sanserver-dc9-43.rpn.online.net` where `sanserver-dc9-43.rpn.online.net` is the RPN SAN IP address.

if it is working jump to installing the required packages, otherwise if you got `Destination Host Unreachable` error, or 100% packet loss،
check the following:

## Make sure your server is configured for Local Area Network (LAN) access  and Access the RPN SAN via the correct Local LAN gateway

RPN-SAN is a private network, so you have to make sure that your server is configured for Local Area Network (LAN) access, and you have to access the RPN SAN via the correct Local LAN gateway.

run `ifconfig` and check that the Local IP address given to your server by scaleway is in the list of working IP addresses. if not then you have to define it.

to define the IP in the correct eth device run `ifconfig` and make sure from the free `ethX` device that uses the correct mac address for the IP address that you have been given. then decide which eth device you want to use , and in this example let assume it `eth2`, and the private local IP given to us is `10.89.4.5`

so to define the private IP address in your server run (i will use ifcfg-eth2 while my device is eth2 , so change it to your device name):

```bash
sudo nano /etc/sysconfig/network-scripts/ifcfg-eth2
```

and add the following lines (note that the netmask and the gateway is given by scaleway):

```bash
DEVICE=eth2
BOOTPROTO=static
ONBOOT=yes
IPADDR=10.89.4.5
NETMASK=255.255.255.128
GATEWAY=10.89.4.1
```

NETMASK and GATEWAY are given by scaleway, so make sure to replace them with the correct values.

now restart the network service:

```bash
systemctl restart NetworkManager
```
and now make sure the IP address is defined by running `ifconfig`

now you have to make sure that the RPN SAN will be accessed via the correct gateway of the Local IP, so you have to add a route to the RPN SAN IP address via the gateway that you have defined in the eth device.

let says that the RPN-SAN IP address is 10.90.254.70 , so you have to tell the server that this IP should be accessed via the eth2, by 

```bash
sudo ip route add 10.90.254.0/24 via 10.89.4.1 dev eth2
```

while 10.89.4.1 is the gateway that you have defined in the eth2 device.

You can see the route using `ip route show`

and then try to ping the RPN SAN IP address again e.g `ping sanserver-dc9-43.rpn.online.net`. if it is working then add the route to the RPN SAN IP address in the `/etc/sysconfig/network-scripts/route-eth2` file by adding the following line in the file (if file not exists then create it) to make the route permanent after reboot by editing the file:

```bash
sudo nano /etc/sysconfig/network-scripts/route-eth2
```

and add the following line:

```bash
10.90.254.0/24 via 10.89.4.1
``` 

where `10.90.254.0/24` is the RPN SAN IP address and `10.89.4.1` is the gateway IP for the IP that you have defined in the eth2 device.


and jump to installing the required packages.


# Installing the required packages

To mount RPN SAN in your server you need to install the following packages (if you want to use scsi devices):

```bash
yum install iscsi-initiator-utils
```

now try to make sure you configured the iscsi , see [How to mount a Scaleway Dedibox RPN-SAN volume on Linux
](https://www.scaleway.com/en/docs/dedibox-network/rpn/how-to/mount-rpn-san-linux/) for more details.

## Check RPN SAN devices

try to discover the RPN SAN devices by running:

```bash
iscsiadm -m discovery -t sendtargets -p sanserver-dc9-43.rpn.online.net
```

you will get something like:

```text
10.90.254.70:3260,1 iqn.2113-67.net.online:1ybontomuwx9
```

now you have to login to the RPN SAN by running:

```bash
iscsiadm -m node -T iqn.2113-67.net.online:1ybontomuwx9 --login
```

if it logged in and you want to enable login on boot, you can run:

```bash
sudo iscsiadm -m node -T iqn.2113-67.net.online:1ybontomuwx9 -o update -n node.startup -v automatic
```

and then check the configuration by running:

```bash
sudo iscsiadm -m node -T iqn.2113-67.net.online:1ybontomuwx9 -o show
```

now Verify iSCSI Sessions by running:

```bash
iscsiadm -m session
```

you will get something like:

```text
tcp: [1] 10.90.254.70:3260,1 iqn.2113-67.net.online:1ybontomuwx9 (non-flash)
```

now Check for Connected Devices by running:

```bash
lsblk
```
This should list any new block devices created by the iSCSI connection

You will get something like:

```text
sda      8:0    0  12.5T  0 disk
├─sda1   8:1    0    1M  0 part
├─sda2   8:2    0    1G  0 part /boot
├─sda3   8:3    0  12.5T  0 part /
└─sda4   8:4    0    5G  0 part [SWAP]
sdb      8:16   0    10T  0 disk
```

Awesome! It looks like you've successfully logged in to the iSCSI target. This means your server is now connected to the SAN and can use it for storage.


## Mount the iSCSI Device (if needed)
   If you see the device whule running lsblk, you may need to format it and mount it if you plan to use it for storage. Make sure to create a filesystem first if it's a new device (in my example it was sdb):
   ```bash
   sudo mkfs.ext4 /dev/sdb  
   ```

   Then create a mount point and mount it:
   ```bash
   sudo mkdir /mnt/iscsi
   sudo mount /dev/sdb /mnt/iscsi
   ```

 ### Automate Mounting on Boot (optional)

If you want the iSCSI device to mount automatically on boot try to get the UUID of  identified your iSCSI device by running (in my example /dev/sdb is the iSCSI device):

```bash
blkid /dev/sdb
```

this will give you something like:

```text
/dev/sdb: UUID="2c889a53-1961-4483-999f-9d7528935e2b" TYPE="ext4"
```

Make sure you configure iscsci to login on boot automatically as described above, then

add an entry to `/etc/fstab` by adding the following line into `/etc/fstab`

Replace `<your-uuid>` with the UUID you got from the previous command. which was `2c889a53-1961-4483-999f-9d7528935e2b` in my example.

```text
UUID=<your-uuid>  /mnt/iscsi  ext4  _netdev,defaults  0  0
```

you can test the the RPN-SAN will be automatically mounted next time you reboot the server by try to reboot your server then check if the RPN-SAN is mounted by running:

```bash
lsblk # to see the connected devices
df -h # to see the mounted devices
```





## Resources and references
- [How to connect a Dedibox to RPN SAN](https://www.scaleway.com/en/docs/dedibox-network/rpn/how-to/connect-rpn-san/)
- [How to mount a Scaleway Dedibox RPN-SAN volume on Linux](https://www.scaleway.com/en/docs/dedibox-network/rpn/how-to/mount-rpn-san-linux/)