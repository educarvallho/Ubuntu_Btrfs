#!/bin/bash
set -e

echo "[1/8] Detectando partições EFI e Btrfs..."

EFI_PART=$(lsblk -pn -o NAME,FSTYPE | grep vfat | awk '{print $1}' | head -n1)
ROOT_PART=$(lsblk -pn -o NAME,FSTYPE | grep btrfs | awk '{print $1}' | head -n1)

OLDROOT="/mnt/oldroot"
NEWROOT="/mnt/newroot"
BACKUP="/tmp/btrfs_backup"

echo "[2/8] Montando volume raiz original..."
mkdir -p "$OLDROOT"
mount "$ROOT_PART" "$OLDROOT"

echo "[3/8] Realizando backup temporário na RAM..."
rsync -aAXHv --exclude=/tmp_btrfs_backup "$OLDROOT/" "$BACKUP/"

echo "[4/8] Criando novos subvolumes no volume raiz..."
for sub in @ @home @cache @log @tmp @snapshots; do
    btrfs subvolume create "$OLDROOT/$sub"
    echo "Subvolume $sub criado."
done

echo "[5/8] Limpando conteúdo do subvolume raiz padrão (subvolid=5)..."
umount "$OLDROOT"
mount -o subvolid=5 "$ROOT_PART" "$OLDROOT"
rm -rf "$OLDROOT"/*

echo "[6/8] Montando novos subvolumes na árvore $NEWROOT..."
mkdir -p "$NEWROOT"
mount -o subvol=@ "$ROOT_PART" "$NEWROOT"
mkdir -p "$NEWROOT"/{home,var/cache,var/log,var/tmp,.snapshots}

mount -o subvol=@home      "$ROOT_PART" "$NEWROOT/home"
mount -o subvol=@cache     "$ROOT_PART" "$NEWROOT/var/cache"
mount -o subvol=@log       "$ROOT_PART" "$NEWROOT/var/log"
mount -o subvol=@tmp       "$ROOT_PART" "$NEWROOT/var/tmp"
mount -o subvol=@snapshots "$ROOT_PART" "$NEWROOT/.snapshots"

echo "[7/8] Restaurando backup nos novos subvolumes..."
rsync -aAXHv "$BACKUP/"             "$NEWROOT/"
rsync -aAXHv "$BACKUP/home/"        "$NEWROOT/home/"
rsync -aAXHv "$BACKUP/var/cache/"   "$NEWROOT/var/cache/"
rsync -aAXHv "$BACKUP/var/log/"     "$NEWROOT/var/log/"
rsync -aAXHv "$BACKUP/var/tmp/"     "$NEWROOT/var/tmp/"

echo "[8/8] Atualizando fstab..."

EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")

cat > "$NEWROOT/etc/fstab" <<EOF
UUID=$EFI_UUID /boot/efi vfat umask=0077 0 1
UUID=$ROOT_UUID /              btrfs subvol=@,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 1
UUID=$ROOT_UUID /home          btrfs subvol=@home,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /var/cache     btrfs subvol=@cache,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /var/log       btrfs subvol=@log,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /var/tmp       btrfs subvol=@tmp,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /.snapshots    btrfs subvol=@snapshots,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
EOF

echo "Sistema reorganizado com subvolumes otimizados e fstab atualizado."
