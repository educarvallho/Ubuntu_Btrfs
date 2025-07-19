#!/bin/bash
set -e

# Detecta a partição EFI e a raiz Btrfs
EFI_PART=$(lsblk -o NAME,FSTYPE | grep vfat | awk '{print "/dev/" $1}' | head -n1)
ROOT_PART=$(lsblk -o NAME,FSTYPE | grep btrfs | awk '{print "/dev/" $1}' | head -n1)

MNT="/mnt"

echo "Montando partição raiz..."
mount $ROOT_PART $MNT

# Cria subvolumes
for sub in @ @home @cache @log @tmp @snapshots; do
  btrfs subvolume create $MNT/$sub
done

# Backup temporário
rsync -aAXHv --exclude=/tmp_btrfs_backup $MNT/ $MNT/tmp_btrfs_backup/

# Remove dados do volume raiz (subvolid=5)
umount $MNT
mount -o subvolid=5 $ROOT_PART $MNT
rm -rf $MNT/*

# Remonta layout novo
mount -o subvol=@ $ROOT_PART $MNT
mkdir -p $MNT/{home,var/cache,var/log,var/tmp,.snapshots}

mount -o subvol=@home       $ROOT_PART $MNT/home
mount -o subvol=@cache      $ROOT_PART $MNT/var/cache
mount -o subvol=@log        $ROOT_PART $MNT/var/log
mount -o subvol=@tmp        $ROOT_PART $MNT/var/tmp
mount -o subvol=@snapshots  $ROOT_PART $MNT/.snapshots

# Restaura dados
rsync -aAXHv $MNT/tmp_btrfs_backup/             $MNT/
rsync -aAXHv $MNT/tmp_btrfs_backup/home/        $MNT/home/
rsync -aAXHv $MNT/tmp_btrfs_backup/var/cache/   $MNT/var/cache/
rsync -aAXHv $MNT/tmp_btrfs_backup/var/log/     $MNT/var/log/
rsync -aAXHv $MNT/tmp_btrfs_backup/var/tmp/     $MNT/var/tmp/

rm -rf $MNT/tmp_btrfs_backup

# Atualiza fstab com UUIDs reais
EFI_UUID=$(blkid -s UUID -o value $EFI_PART)
ROOT_UUID=$(blkid -s UUID -o value $ROOT_PART)

cat > $MNT/etc/fstab <<EOF
UUID=$EFI_UUID /boot/efi vfat umask=0077 0 1
UUID=$ROOT_UUID /              btrfs subvol=@,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 1
UUID=$ROOT_UUID /home          btrfs subvol=@home,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /var/cache     btrfs subvol=@cache,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /var/log       btrfs subvol=@log,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /var/tmp       btrfs subvol=@tmp,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /.snapshots    btrfs subvol=@snapshots,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
EOF

echo "Sistema reorganizado com subvolumes otimizados e fstab atualizado."
