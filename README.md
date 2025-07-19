# Instalação do Ubuntu 24.04 com Btrfs, Subvolumes Otimizados e Snapper

## Visão Geral

Instalaremos o Ubuntu 24.04 em modo UEFI, usando o sistema de arquivos Btrfs com os seguintes subvolumes:

- @           → /  (root)
- @home       → /home
- @cache      → /var/cache
- @log        → /var/log
- @tmp        → /var/tmp
- @snapshots  → /.snapshots

Snapper será usado para criar snapshots automáticos e restaurar o sistema se necessário. Usaremos `grub-btrfs` para integrá-los ao GRUB.

---

## 1. Requisitos

- Ubuntu 24.04 Live CD
- Instalador padrão da ISO do Ubuntu
- Particionamento padrão do instalador, com:
  - Partição EFI (FAT32)
  - Partição Btrfs

---

## 2. Executar script de organização dos subvolumes (via Live CD)

### 🔧 Execução rápida via GitHub (recomendado)
Você pode executar o script diretamente do repositório com `curl` ou `wget` utilizando `sudo`:

```bash
# Usando curl
curl -sL https://raw.githubusercontent.com/educarvallho/Ubuntu_Btrfs/refs/heads/main/btrfs_subvolumes.sh | sudo bash

# Ou usando wget
wget -qO- https://raw.githubusercontent.com/educarvallho/Ubuntu_Btrfs/refs/heads/main/btrfs_subvolumes.sh | sudo bash
```

Caso prefira realizar as etapas manualmente, siga as instruções abaixo:

### Acesse o terminal como root:
```bash
sudo su
```

### Salve e execute o script manualmente:
```bash
nano btrfs_subvolumes.sh
```
Cole o conteúdo abaixo:
```bash
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
```

Torne executável e rode:
```bash
chmod +x btrfs_subvolumes.sh
./btrfs_subvolumes.sh
```

---

## 3. Primeiro boot e pós-instalação

Após o primeiro boot no sistema reorganizado:

Monte a pasta de snapshots:
```bash
sudo mkdir -p /.snapshots
sudo mount -a
```

Em seguida, instale os pacotes:
```bash
sudo apt update
sudo apt install snapper grub-btrfs btrfs-progs
```

Crie a configuração Snapper:
```bash
sudo snapper -c root create-config /
```

Inicie o primeiro snapshot:
```bash
sudo snapper -c root create --description "Estado inicial"
```

Atualize initramfs e grub:
```bash
sudo update-initramfs -u
sudo update-grub
```

---

## Migrar @home para outro disco (opcional)

Você pode mover o subvolume `@home` para outro HD/SSD formatado com Btrfs.

### 1. Formate o novo disco
```bash
sudo mkfs.btrfs -f /dev/sdb1
```

### 2. Monte em ponto temporário
```bash
sudo mkdir /mnt/new_home_disk
sudo mount /dev/sdb1 /mnt/new_home_disk
```

### 3. Crie o subvolume `@home`
```bash
sudo btrfs subvolume create /mnt/new_home_disk/@home
```

### 4. Copie os dados
```bash
sudo rsync -aAXHv /home/ /mnt/new_home_disk/@home/
```

### 5. Atualize o fstab

Edite o arquivo:
```bash
sudo nano /etc/fstab
```

Substitua a linha antiga pelo UUID do novo disco:
```diff
- UUID=<UUID_do_SSD> /home btrfs subvol=@home,defaults,noatime,... 0 0
+ UUID=<UUID_novo_HD> /home btrfs subvol=@home,defaults=noatime,... 0 0
```

Você pode obter o novo UUID com:
```bash
blkid /dev/sdb1
```

### 6. Monte o novo ponto de forma definitiva
```bash
sudo umount /mnt/new_home_disk
sudo rmdir /mnt/new_home_disk
sudo mkdir /mnt/home
sudo mount -o subvol=@home /dev/sdb1 /mnt/home
```

Verifique:
```bash
findmnt /home
```

Se tudo estiver correto, os dados estarão no novo disco e funcionando normalmente.

---

## Notas finais

- O Snapper reconhecerá normalmente a pasta `.snapshots` montada de `@snapshots`.
- Evita necessidade de criar essa pasta manualmente após cada reboot.
- Snapper é mais completo que Timeshift e dispensa o uso paralelo.

Sistema pronto para snapshots automáticos com rollback pelo GRUB.

