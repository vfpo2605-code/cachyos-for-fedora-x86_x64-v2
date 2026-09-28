#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Rebuild oficial do kernel-cachyos para x86-64-v2
# Fedora / RPM / CachyOS
#
# Correções consolidadas:
# - COPR atual via origin/HEAD
# - x86-64-v3 -> x86-64-v2
# - Release não depende de "cachyos2"
# - Source0 obtido do SPEC expandido via rpmspec -P
# - tag -> commit usando o SHA "peeled" (refs/tags/TAG^{})
# - commit exato conferido antes do archive
# - Source0 local sobrescrito após spectool
# - rpmbuild só é considerado concluído se gerar RPMs
# - validação final limitada aos artefatos realmente gerados
# - instala todos os RPMs gerados
# - não remove kernels antigos
# - não altera bootloader
# - não tenta validar config no meta-pacote
# ============================================================

PROJECT_NAME="kernel-cachyos-v2"

COPR_REPO_URL="https://github.com/CachyOS/copr-linux-cachyos"
KERNEL_REPO_URL="https://github.com/CachyOS/linux"

SPEC_RELATIVE_PATH="sources/kernel-cachyos-bore/kernel-cachyos.spec"

BUILD_ROOT="${HOME}/${PROJECT_NAME}-$(date +%Y%m%d-%H%M%S)-$$"

COPR_REPO_DIR="${BUILD_ROOT}/copr-linux-cachyos"
KERNEL_REPO_DIR="${BUILD_ROOT}/linux"
SOURCE_TARBALL_DIR="${BUILD_ROOT}/sources"

TOPDIR="${BUILD_ROOT}/rpmbuild"

SPEC_FILE="${COPR_REPO_DIR}/${SPEC_RELATIVE_PATH}"

LOG_FILE="${BUILD_ROOT}/build.log"


# ------------------------------------------------------------
# Cores
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    printf '%b\n' "${BLUE}[INFO]${NC} $*"
}

ok() {
    printf '%b\n' "${GREEN}[OK]${NC} $*"
}

warn() {
    printf '%b\n' "${YELLOW}[AVISO]${NC} $*"
}

die() {
    printf '%b\n' "${RED}[ERRO]${NC} $*" >&2
    exit 1
}


# ------------------------------------------------------------
# Tratamento de erro
# ------------------------------------------------------------

trap '
    rc=$?
    printf "\n%b\n" "${RED}[ERRO FATAL]${NC} O script terminou com código ${rc}."
    printf "Log: %s\n" "$LOG_FILE"
    exit "$rc"
' ERR


# ------------------------------------------------------------
# Pré-requisitos mínimos
# ------------------------------------------------------------

info "Verificando pré-requisitos mínimos..."

for cmd in \
    git \
    rpm \
    dnf \
    sudo \
    find \
    grep \
    sed \
    awk \
    sort \
    tar
do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Comando obrigatório não encontrado: $cmd"
done

ok "Pré-requisitos mínimos encontrados."


# ------------------------------------------------------------
# Autenticar sudo cedo
# ------------------------------------------------------------

info "Validando autenticação sudo..."

sudo -v

ok "sudo autenticado."


# ------------------------------------------------------------
# Criar diretórios
# ------------------------------------------------------------

mkdir -p \
    "$BUILD_ROOT" \
    "$SOURCE_TARBALL_DIR" \
    "$TOPDIR/BUILD" \
    "$TOPDIR/BUILDROOT" \
    "$TOPDIR/RPMS" \
    "$TOPDIR/SOURCES" \
    "$TOPDIR/SPECS" \
    "$TOPDIR/SRPMS"


# ------------------------------------------------------------
# Log
# ------------------------------------------------------------

exec > >(tee -a "$LOG_FILE") 2>&1


printf '\n'
printf '%s\n' '============================================================'
printf '%s\n' '  KERNEL CACHYOS x86-64-v2'
printf '%s\n' '============================================================'
printf 'Build root       : %s\n' "$BUILD_ROOT"
printf 'COPR repository  : %s\n' "$COPR_REPO_URL"
printf 'Kernel repository: %s\n' "$KERNEL_REPO_URL"
printf 'SPEC             : %s\n' "$SPEC_RELATIVE_PATH"
printf 'Versão upstream  : descoberta automaticamente'
printf '%s\n' '============================================================'
printf '\n'


# ------------------------------------------------------------
# Dependências de compilação
# ------------------------------------------------------------

info "Instalando dependências de compilação..."

sudo dnf install -y \
    bc \
    bison \
    dwarves \
    elfutils-devel \
    flex \
    gcc \
    gettext-devel \
    kmod \
    make \
    openssl \
    openssl-devel \
    perl-Carp \
    perl-devel \
    perl-generators \
    perl-interpreter \
    python3-devel \
    python3-pyyaml \
    python-srpm-macros \
    clang \
    lld \
    llvm \
    rpm-build \
    rpmdevtools

ok "Dependências instaladas."


# ------------------------------------------------------------
# Verificar ferramentas após instalação
# ------------------------------------------------------------

for cmd in \
    git \
    rpmbuild \
    rpmspec \
    rpm \
    dnf \
    sudo \
    spectool \
    find \
    grep \
    sed \
    awk \
    sort \
    tar \
    tee
do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Ferramenta obrigatória não encontrada após instalação: $cmd"
done

ok "Ferramentas de build disponíveis."


# ------------------------------------------------------------
# Clonar repositório atual do CachyOS
# ------------------------------------------------------------

info "Clonando o repositório atual do CachyOS..."

git clone \
    --filter=blob:none \
    --no-checkout \
    "$COPR_REPO_URL" \
    "$COPR_REPO_DIR"

git -C "$COPR_REPO_DIR" checkout \
    --detach \
    origin/HEAD

ACTUAL_COPR_COMMIT="$(
    git -C "$COPR_REPO_DIR" rev-parse HEAD
)"

ok "COPR atual:"
printf '%s\n\n' "$ACTUAL_COPR_COMMIT"


# ------------------------------------------------------------
# Verificar SPEC
# ------------------------------------------------------------

[[ -f "$SPEC_FILE" ]] ||
    die "SPEC não encontrado: $SPEC_FILE"

ok "SPEC encontrado:"
printf '%s\n\n' "$SPEC_FILE"


# ------------------------------------------------------------
# Verificar características do SPEC
# ------------------------------------------------------------

info "Verificando características do kernel CachyOS..."

grep -Eq \
    '^[[:space:]]*%define[[:space:]]+_hz_tick[[:space:]]+1000([[:space:]]*)$' \
    "$SPEC_FILE" ||
    die "O SPEC não está configurado para 1000 Hz."

grep -Eq \
    '^[[:space:]]*%define[[:space:]]+_build_lto[[:space:]]+0([[:space:]]*)$' \
    "$SPEC_FILE" ||
    die "O SPEC não está configurado com LTO desativado."

grep -Eq \
    '^[[:space:]]*%define[[:space:]]+_x86_64_lvl[[:space:]]+' \
    "$SPEC_FILE" ||
    die "O SPEC não contém _x86_64_lvl."

grep -Eq \
    '^[[:space:]]*scripts/config[[:space:]]+-e[[:space:]]+CACHY[[:space:]]+-e[[:space:]]+SCHED_BORE' \
    "$SPEC_FILE" ||
    die "O SPEC não contém CACHY + BORE."

grep -Eq \
    '^[[:space:]]*scripts/config[[:space:]]+--set-val[[:space:]]+X86_64_VERSION[[:space:]]+' \
    "$SPEC_FILE" ||
    die "O SPEC não contém X86_64_VERSION."

ok "1000 Hz detectado."
ok "LTO desativado detectado."
ok "CachyOS detectado."
ok "BORE detectado."
ok "X86_64_VERSION detectado."


# ------------------------------------------------------------
# Alterar x86-64-v3 para x86-64-v2
# ------------------------------------------------------------

info "Configurando x86-64-v2..."

X86_LEVEL_COUNT="$(
    grep -Ec \
        '^[[:space:]]*%define[[:space:]]+_x86_64_lvl[[:space:]]+' \
        "$SPEC_FILE"
)"

[[ "$X86_LEVEL_COUNT" == "1" ]] ||
    die "Esperava exatamente uma definição de _x86_64_lvl."

CURRENT_X86_LEVEL="$(
    awk '
        /^[[:space:]]*%define[[:space:]]+_x86_64_lvl[[:space:]]+/ {
            print $3
        }
    ' "$SPEC_FILE"
)"

[[ "$CURRENT_X86_LEVEL" == "3" ]] ||
    die "O SPEC não está em x86-64-v3. Valor encontrado: $CURRENT_X86_LEVEL"

sed -i \
    -E \
    's/^([[:space:]]*%define[[:space:]]+_x86_64_lvl[[:space:]]+)3([[:space:]]*)$/\12\2/' \
    "$SPEC_FILE"

NEW_X86_LEVEL="$(
    awk '
        /^[[:space:]]*%define[[:space:]]+_x86_64_lvl[[:space:]]+/ {
            print $3
        }
    ' "$SPEC_FILE"
)"

[[ "$NEW_X86_LEVEL" == "2" ]] ||
    die "Falha ao alterar _x86_64_lvl para 2."

ok "SPEC configurado para x86-64-v2."


# ------------------------------------------------------------
# Ajustar Release sem assumir cachyos2
# ------------------------------------------------------------

info "Ajustando Release do RPM..."

RELEASE_COUNT="$(
    grep -Ec '^Release:[[:space:]]+' "$SPEC_FILE"
)"

[[ "$RELEASE_COUNT" == "1" ]] ||
    die "Esperava exatamente uma linha Release."

RELEASE_LINE="$(
    grep -E '^Release:[[:space:]]+' "$SPEC_FILE"
)"

RELEASE_VALUE="${RELEASE_LINE#Release:}"
RELEASE_VALUE="${RELEASE_VALUE#"${RELEASE_VALUE%%[![:space:]]*}"}"

[[ -n "$RELEASE_VALUE" ]] ||
    die "Release vazio."

if [[ "$RELEASE_VALUE" == *.v2* ]]; then

    FINAL_RELEASE="$RELEASE_VALUE"

else

    MACRO_PART=""
    BASE_RELEASE="$RELEASE_VALUE"

    if [[ "$RELEASE_VALUE" == *'%{'* ]]; then
        BASE_RELEASE="${RELEASE_VALUE%%\%\{*}"
        MACRO_PART="${RELEASE_VALUE:${#BASE_RELEASE}}"
    fi

    [[ -n "$BASE_RELEASE" ]] ||
        die "Não foi possível separar a base do Release: $RELEASE_VALUE"

    NEW_RELEASE_VALUE="${BASE_RELEASE}.v2${MACRO_PART}"

    sed -i \
        -E \
        "s|^Release:[[:space:]]+.*$|Release:        ${NEW_RELEASE_VALUE}|" \
        "$SPEC_FILE"

fi

FINAL_RELEASE="$(
    awk '
        /^Release:/ {
            sub(/^Release:[[:space:]]*/, "", $0)
            print
        }
    ' "$SPEC_FILE"
)"

[[ "$FINAL_RELEASE" == *.v2* ]] ||
    die "Falha ao ajustar Release para .v2: $FINAL_RELEASE"

ok "Release final:"
printf '%s\n\n' "$FINAL_RELEASE"


# ------------------------------------------------------------
# Copiar SPEC para o rpmbuild
# ------------------------------------------------------------

cp -f \
    "$SPEC_FILE" \
    "$TOPDIR/SPECS/kernel-cachyos.spec"


# ------------------------------------------------------------
# Descobrir automaticamente Source0 pelo SPEC expandido
# ------------------------------------------------------------

info "Descobrindo a versão upstream definida pelo SPEC..."

EXPANDED_SPEC="$(
    rpmspec \
        -P \
        "$TOPDIR/SPECS/kernel-cachyos.spec"
)"

[[ -n "$EXPANDED_SPEC" ]] ||
    die "rpmspec não produziu um SPEC expandido."

SOURCE0_URL="$(
    printf '%s\n' "$EXPANDED_SPEC" |
        awk '
            /^Source0:[[:space:]]*/ {
                sub(/^Source0:[[:space:]]*/, "", $0)
                print
                exit
            }
        '
)"

[[ -n "$SOURCE0_URL" ]] ||
    die "Não foi possível obter Source0 do SPEC expandido."

info "Source0 resolvido:"
printf '%s\n' "$SOURCE0_URL"

SOURCE0_FILE="${SOURCE0_URL##*/}"

[[ "$SOURCE0_FILE" == *.tar.gz ]] ||
    die "Source0 não aponta para um tarball .tar.gz válido: $SOURCE0_FILE"

UPSTREAM_TAG="${SOURCE0_FILE%.tar.gz}"

[[ "$UPSTREAM_TAG" == cachyos-* ]] ||
    die "Não foi possível determinar um tag CachyOS válido: $UPSTREAM_TAG"

SOURCE_TARBALL="${SOURCE_TARBALL_DIR}/linux-${UPSTREAM_TAG}.tar.gz"

ok "Tag upstream descoberto automaticamente:"
printf '%s\n\n' "$UPSTREAM_TAG"


# ------------------------------------------------------------
# Descobrir o commit REAL do tag
#
# IMPORTANTE:
# refs/tags/TAG pode retornar o objeto da tag anotada.
# refs/tags/TAG^{} retorna o commit para o qual ela aponta.
# ------------------------------------------------------------

info "Descobrindo o commit correspondente ao tag upstream..."

UPSTREAM_COMMIT="$(
    git ls-remote \
        "$KERNEL_REPO_URL" \
        "refs/tags/${UPSTREAM_TAG}^{}" |
        awk 'NR == 1 { print $1 }'
)"

[[ "$UPSTREAM_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
    die "Não foi possível obter o commit real para o tag ${UPSTREAM_TAG}."

ok "Commit upstream descoberto:"
printf '%s\n\n' "$UPSTREAM_COMMIT"


# ------------------------------------------------------------
# Mostrar versão final
# ------------------------------------------------------------

printf '%s\n' '============================================================'
printf '%s\n' '  VERSÃO DESCOBERTA'
printf '%s\n' '============================================================'
printf 'COPR commit  : %s\n' "$ACTUAL_COPR_COMMIT"
printf 'Kernel tag   : %s\n' "$UPSTREAM_TAG"
printf 'Kernel commit: %s\n' "$UPSTREAM_COMMIT"
printf 'x86-64 level : v2\n'
printf '%s\n' '============================================================'
printf '\n'


# ------------------------------------------------------------
# Obter código-fonte exato
# ------------------------------------------------------------

info "Obtendo código-fonte exato do kernel CachyOS..."

mkdir -p "$KERNEL_REPO_DIR"

git -C "$KERNEL_REPO_DIR" init

git -C "$KERNEL_REPO_DIR" remote add origin \
    "$KERNEL_REPO_URL"

git -C "$KERNEL_REPO_DIR" fetch \
    --depth=1 \
    --filter=blob:none \
    origin \
    "$UPSTREAM_COMMIT"

git -C "$KERNEL_REPO_DIR" checkout \
    --detach \
    "$UPSTREAM_COMMIT"

ACTUAL_KERNEL_COMMIT="$(
    git -C "$KERNEL_REPO_DIR" rev-parse HEAD
)"

[[ "$ACTUAL_KERNEL_COMMIT" == "$UPSTREAM_COMMIT" ]] ||
    die "Commit do kernel incorreto."

ok "Commit exato do kernel confirmado:"
printf '%s\n\n' "$ACTUAL_KERNEL_COMMIT"


# ------------------------------------------------------------
# Criar tarball local
# ------------------------------------------------------------

info "Criando tarball local do kernel..."

rm -f "$SOURCE_TARBALL"

git -C "$KERNEL_REPO_DIR" archive \
    --format=tar.gz \
    --prefix="linux-${UPSTREAM_TAG}/" \
    -o "$SOURCE_TARBALL" \
    "$UPSTREAM_COMMIT"

[[ -s "$SOURCE_TARBALL" ]] ||
    die "Falha ao criar Source0."

ok "Tarball do kernel criado."


# ------------------------------------------------------------
# Copiar Source0 local
# ------------------------------------------------------------

cp -f \
    "$SOURCE_TARBALL" \
    "$TOPDIR/SOURCES/linux-${UPSTREAM_TAG}.tar.gz"


# ------------------------------------------------------------
# Baixar demais Sources
# ------------------------------------------------------------

info "Obtendo os demais Sources do SPEC..."

pushd "$TOPDIR/SOURCES" >/dev/null

spectool \
    --get-files \
    "$TOPDIR/SPECS/kernel-cachyos.spec"

popd >/dev/null


# ------------------------------------------------------------
# Garantir novamente que Source0 seja o tarball exato
# ------------------------------------------------------------

cp -f \
    "$SOURCE_TARBALL" \
    "$TOPDIR/SOURCES/linux-${UPSTREAM_TAG}.tar.gz"


# ------------------------------------------------------------
# Validar SPEC final
# ------------------------------------------------------------

info "Validando SPEC..."

rpmspec \
    -P \
    "$TOPDIR/SPECS/kernel-cachyos.spec" \
    >/dev/null

ok "SPEC válido."


# ------------------------------------------------------------
# Limpar saídas desta execução
# ------------------------------------------------------------

rm -rf "$TOPDIR/BUILD/"*
rm -rf "$TOPDIR/BUILDROOT/"*
rm -rf "$TOPDIR/RPMS/"*
rm -rf "$TOPDIR/SRPMS/"*


# ------------------------------------------------------------
# Compilar
# ------------------------------------------------------------

info "Iniciando rpmbuild..."

if rpmbuild \
    --define "_topdir $TOPDIR" \
    -ba \
    "$TOPDIR/SPECS/kernel-cachyos.spec"
then
    ok "rpmbuild terminou com sucesso."
else
    rc=$?
    printf '\n'
    printf '%b\n' "${RED}[ERRO]${NC} rpmbuild falhou com código ${rc}."
    printf 'Isso é uma falha real de BUILD/EMBALAMENTO.\n'
    printf 'Log: %s\n' "$LOG_FILE"
    exit "$rc"
fi


# ------------------------------------------------------------
# Verificar RPMs realmente gerados
# ------------------------------------------------------------

printf '\n'
info "Localizando RPMs gerados..."

mapfile -t RPM_FILES < <(
    find "$TOPDIR/RPMS" \
        -type f \
        -name '*.rpm' \
        -print |
        sort
)

(( ${#RPM_FILES[@]} > 0 )) ||
    die "O rpmbuild terminou, mas nenhum RPM foi encontrado em $TOPDIR/RPMS."

printf '\n'
printf '%s\n' '============================================================'
printf '%s\n' '  RPMs GERADOS'
printf '%s\n' '============================================================'

for rpm_file in "${RPM_FILES[@]}"; do
    rpm -qp \
        --qf '  %{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' \
        "$rpm_file"
done

printf '%s\n' '============================================================'


# ------------------------------------------------------------
# Validar apenas os artefatos RPM básicos
# ------------------------------------------------------------

info "Validando arquiteturas dos RPMs..."

for rpm_file in "${RPM_FILES[@]}"; do

    arch="$(
        rpm -qp \
            --qf '%{ARCH}\n' \
            "$rpm_file"
    )"

    case "$arch" in
        x86_64|noarch)
            ;;
        *)
            die "Arquitetura inesperada em $(basename "$rpm_file"): $arch"
            ;;
    esac

done

ok "Arquiteturas válidas."


# ------------------------------------------------------------
# Verificar pacotes obrigatórios
# ------------------------------------------------------------

EXPECTED_PACKAGES=(
    "kernel-cachyos"
    "kernel-cachyos-core"
    "kernel-cachyos-modules"
    "kernel-cachyos-devel"
    "kernel-cachyos-devel-matched"
)

info "Verificando pacotes obrigatórios..."

for pkg in "${EXPECTED_PACKAGES[@]}"; do

    if find "$TOPDIR/RPMS" \
        -type f \
        -name "${pkg}-*.rpm" |
        grep -q .
    then
        ok "$pkg encontrado."
    else
        die "$pkg não foi gerado."
    fi

done


# ------------------------------------------------------------
# Mostrar SRPM
# ------------------------------------------------------------

printf '\n'
printf '%s\n' 'SRPM gerado:'

find "$TOPDIR/SRPMS" \
    -type f \
    -name '*.src.rpm' \
    -printf '  %f\n' |
sort || true


# ------------------------------------------------------------
# Instalar todos os RPMs gerados
#
# Não remove kernels antigos.
# Não altera bootloader manualmente.
# O DNF faz a transação de instalação.
# ------------------------------------------------------------

info "Instalando os RPMs gerados..."

sudo -v

sudo dnf install -y "${RPM_FILES[@]}"

ok "Todos os RPMs gerados foram instalados."


# ------------------------------------------------------------
# Final
# ------------------------------------------------------------

printf '\n'
printf '%s\n' '============================================================'
printf '%s\n' '  KERNEL CACHYOS x86-64-v2 INSTALADO COM SUCESSO'
printf '%s\n' '============================================================'
printf 'COPR commit : %s\n' "$ACTUAL_COPR_COMMIT"
printf 'Kernel tag  : %s\n' "$UPSTREAM_TAG"
printf 'Kernel SHA  : %s\n' "$UPSTREAM_COMMIT"
printf 'Release     : %s\n' "$FINAL_RELEASE"
printf 'RPMs        : %s\n' "$TOPDIR/RPMS"
printf 'SRPM        : %s\n' "$TOPDIR/SRPMS"
printf 'Log         : %s\n' "$LOG_FILE"
printf 'Build root  : %s\n' "$BUILD_ROOT"
printf '%s\n' '============================================================'
printf '\n'

ok "x86-64-v2 configurado"
ok "CachyOS + BORE + 1000 Hz preservados pelo SPEC"
ok "rpmbuild terminou e gerou RPMs"
ok "Pacotes obrigatórios foram gerados"
ok "Todos os RPMs gerados foram instalados"
ok "Kernel antigo preservado"

exit 0
