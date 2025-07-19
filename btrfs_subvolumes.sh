#!/bin/bash
set -e

echo "Iniciando reorganização do Btrfs com subvolumes otimizados..."

# Detecta partição EFI e raiz Btrfs
EFI_PART=$(blkid | grep "vfat" | cut -d: -f1 | head -n1)
ROOT_PART=$(blkid | grep "btrfs" | cut -d: -f1 | head -n1)

# Define pontos de montagem temporários
OLDROOT="/mnt/oldroot"
NEWROOT="/mnt/newroot"
BACKUP="/tmp/backup"

echo "Criando pontos de montagem..."
mkdir -p $OLDROOT $NEWROOT $BACKUP

echo "Montando subvolume raiz padrão (subvolid=5) em $OLDROOT..."
mount -o subvolid=5 $ROOT_PART $OLDROOT

echo "Fazendo backup temporário dos dados para $BACKUP..."
rsync -aAXHv --exclude=/tmp/backup $OLDROOT/ $BACKUP/

echo "Criando novos subvolumes no volume raiz..."
for sub in @ @home @cache @log @tmp @snapshots; do
  if btrfs subvolume show $OLDROOT/$sub &>/dev/null; then
    echo "Subvolume $sub já existe, pulando criação."
  else
    btrfs subvolume create $OLDROOT/$sub
    echo "Subvolume $sub criado."
  fi
done

echo "Limpando conteúdo do subvolume raiz padrão (subvolid=5)..."
rm -rf $OLDROOT/*

echo "Montando novos subvolumes na árvore $NEWROOT..."
mount -o subvol=@ $ROOT_PART $NEWROOT
mkdir -p $NEWROOT/{home,var/cache,var/log,var/tmp,.snapshots}
mount -o subvol=@home      $ROOT_PART $NEWROOT/home
mount -o subvol=@cache     $ROOT_PART $NEWROOT/var/cache
mount -o subvol=@log       $ROOT_PART $NEWROOT/var/log
mount -o subvol=@tmp       $ROOT_PART $NEWROOT/var/tmp
mount -o subvol=@snapshots $ROOT_PART $NEWROOT/.snapshots

echo "Restaurando dados do backup para os subvolumes..."
rsync -aAXHv $BACKUP/             $NEWROOT/
rsync -aAXHv $BACKUP/home/        $NEWROOT/home/
rsync -aAXHv $BACKUP/var/cache/   $NEWROOT/var/cache/
rsync -aAXHv $BACKUP/var/log/     $NEWROOT/var/log/
rsync -aAXHv $BACKUP/var/tmp/     $NEWROOT/var/tmp/

echo "Removendo backup temporário..."
rm -rf $BACKUP

# Atualiza fstab com UUIDs reais
EFI_UUID=$(blkid -s UUID -o value $EFI_PART)
ROOT_UUID=$(blkid -s UUID -o value $ROOT_PART)

echo "Atualizando /etc/fstab no novo sistema..."

cat > $NEWROOT/etc/fstab <<EOF
UUID=$EFI_UUID /boot/efi vfat umask=0077 0 1
UUID=$ROOT_UUID /              btrfs subvol=@,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 1
UUID=$ROOT_UUID /home          btrfs subvol=@home,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /var/cache     btrfs subvol=@cache,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /var/log       btrfs subvol=@log,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /var/tmp       btrfs subvol=@tmp,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
UUID=$ROOT_UUID /.snapshots    btrfs subvol=@snapshots,defaults,noatime,space_cache,ssd,autodefrag,discard=async,compress=zstd 0 0
EOF

echo "Desmontando pontos temporários..."
umount $OLDROOT
umount $NEWROOT

echo "Sistema reorganizado com subvolumes otimizados e fstab atualizado."
