# CachyOS Kernel x86-64-v2 Builder para Fedora

![Fedora](https://img.shields.io/badge/Fedora-44-51a2da?logo=fedora&logoColor=white)
![Kernel](https://img.shields.io/badge/CachyOS-kernel--cachyos-orange)
![Arquitetura](https://img.shields.io/badge/x86--64-v2-2ea44f)
![Formato](https://img.shields.io/badge/packaging-RPM-red)
![Shell](https://img.shields.io/badge/script-Bash-4EAA25?logo=gnubash&logoColor=white)

> Rebuild local do **kernel-cachyos oficial** para Fedora, com target **x86-64-v2**, mantendo a configuração e o fluxo de empacotamento do CachyOS e evitando a exigência de x86-64-v3.

## O que este projeto é

Este projeto **não é um novo kernel forkado** e não pretende ser uma variante oficial do CachyOS.

Ele pega o empacotamento RPM do `kernel-cachyos` no repositório oficial do CachyOS, acompanha a versão upstream definida pelo SPEC, altera o nível de ISA de `x86-64-v3` para `x86-64-v2`, recompila localmente com `rpmbuild` e instala os RPMs resultantes com DNF.

Fontes usadas pelo script:

- **Kernel:** https://github.com/CachyOS/linux
- **Empacotamento COPR:** https://github.com/CachyOS/copr-linux-cachyos
- **SPEC usado:** `sources/kernel-cachyos-bore/kernel-cachyos.spec`

## Por que ele existe

O objetivo é atender máquinas que conseguem executar **x86-64-v2**, mas não **x86-64-v3**, e ainda assim precisam ou preferem usar o `kernel-cachyos`.

A mudança central feita pelo script é:

```text
x86-64-v3
     ↓
x86-64-v2
```

O restante do fluxo procura preservar o que já está definido pelo SPEC do CachyOS, em vez de recriar manualmente a configuração do kernel.

## O que o script faz

O arquivo `build-kernel-cachyos-v2.sh` executa, em ordem:

1. verifica ferramentas básicas;
2. autentica `sudo` antes da compilação;
3. instala as dependências de build;
4. baixa o repositório atual de empacotamento do CachyOS;
5. usa `origin/HEAD` para acompanhar a branch padrão atual;
6. localiza o SPEC `kernel-cachyos.spec`;
7. verifica propriedades esperadas do SPEC, incluindo 1000 Hz, LTO desativado, CACHY, BORE e `X86_64_VERSION`;
8. exige que o SPEC comece em `_x86_64_lvl 3` e então altera para `2`;
9. acrescenta `.v2` ao `Release` sem depender de o release upstream ser exatamente `cachyos2`;
10. expande o SPEC com `rpmspec -P`;
11. obtém o `Source0` real do SPEC expandido;
12. deriva automaticamente o tag upstream a partir do nome do tarball;
13. resolve o commit real da tag usando `refs/tags/TAG^{}`;
14. baixa exatamente esse commit;
15. confere que o `HEAD` baixado é o commit esperado;
16. gera localmente o tarball do kernel a partir do commit conferido;
17. busca os demais Sources com `spectool`;
18. recoloca o tarball local como `Source0`;
19. valida novamente o SPEC expandido;
20. executa `rpmbuild -ba`;
21. confirma que RPMs foram realmente gerados;
22. confere as arquiteturas dos RPMs;
23. confere a existência dos pacotes principais esperados;
24. instala todos os RPMs gerados numa única transação DNF.

## O que ele deliberadamente não faz

O script **não**:

- remove kernels antigos;
- remove o kernel em execução;
- mexe manualmente no GRUB;
- altera o bootloader para selecionar um kernel específico;
- troca o `kernel-cachyos` por `server`, `lts`, `rt`, `lto` ou outro flavor;
- faz fallback silencioso para x86-64-v3;
- valida o `config` procurando-o obrigatoriamente dentro do meta-pacote `kernel-cachyos`;
- copia manualmente kernel, módulos ou arquivos de boot para locais do sistema.

A instalação fica a cargo do gerenciador de pacotes RPM/DNF, usando os pacotes efetivamente gerados pelo build.

## Compatibilidade

O alvo do projeto é **Fedora/RPM** e um processador que suporte **x86-64-v2**.

Este script não transforma um processador incompatível em x86-64-v2. Antes de compilar, verifique a capacidade da CPU. Em Fedora, a infraestrutura do carregador x86-64 pode ser consultada com:

```bash
/lib64/ld-linux-x86-64.so.2 --help
```

O projeto é especialmente útil no cenário em que a CPU suporta v2, mas a máquina não pode executar software exigindo v3.

## Requisitos de software

O script instala suas dependências principais automaticamente. Entre as ferramentas usadas no fluxo estão:

```text
bash
sudo
dnf
git
rpm
rpmbuild
rpmspec
spectool
make
gcc
clang
llvm
lld
```

A lista efetiva de pacotes está dentro do próprio script e deve ser tratada como a fonte de verdade do fluxo de build.

## Uso

Clone o repositório, entre nele e torne o script executável:

```bash
git clone <URL-DO-SEU-REPOSITORIO>
cd kernel-cachyos-v2
chmod +x build-kernel-cachyos-v2.sh
```

Execute:

```bash
./build-kernel-cachyos-v2.sh
```

O script cria um diretório de build com timestamp e PID no diretório pessoal do usuário, por exemplo:

```text
~/kernel-cachyos-v2-20260920-112000-12345/
```

Dentro dele ficam o repositório temporário, o `rpmbuild`, os RPMs, o SRPM e o log.

## O fluxo em uma imagem

```text
┌──────────────────────────────────────────────┐
│ CachyOS COPR packaging                       │
│ kernel-cachyos.spec                          │
└──────────────────────┬───────────────────────┘
                       │
                 rpmspec -P
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ Source0                                      │
│ versão/tag definidos pelo SPEC              │
└──────────────────────┬───────────────────────┘
                       │
                 Git tag peeled
                 refs/tags/TAG^{}
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ Commit upstream exato                        │
└──────────────────────┬───────────────────────┘
                       │
                 checkout exato
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ CachyOS Linux source                         │
└──────────────────────┬───────────────────────┘
                       │
                 v3 → v2 no SPEC
                       │
                       ▼
                 rpmbuild -ba
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ kernel-cachyos RPMs                          │
│ meta / core / modules / devel / matched      │
└──────────────────────┬───────────────────────┘
                       │
                      DNF
                       │
                       ▼
┌──────────────────────────────────────────────┐
│ Fedora executando o kernel CachyOS x86-64-v2 │
└──────────────────────────────────────────────┘
```

## Pacotes esperados

O script exige que sejam encontrados RPMs correspondentes a:

```text
kernel-cachyos
kernel-cachyos-core
kernel-cachyos-modules
kernel-cachyos-devel
kernel-cachyos-devel-matched
```

O conjunto exato de arquivos, versionamento e release depende da revisão upstream do SPEC usada naquela execução.

## Como o build escolhe a versão do kernel

O script **não depende de uma versão fixa hard-coded**.

Primeiro ele expande o SPEC:

```bash
rpmspec -P kernel-cachyos.spec
```

Depois lê `Source0` do SPEC expandido. Isso é importante porque o SPEC pode conter macros RPM e referências dinâmicas que não devem ser tratadas como texto literal.

Em seguida, o nome do arquivo `Source0` é usado para descobrir o tag upstream.

Exemplo conceitual:

```text
Source0 → cachyos-<versão>-1.tar.gz
                   │
                   ▼
          cachyos-<versão>-1
```

## Como o commit upstream é protegido

Para tags anotadas, o script não pega cegamente o primeiro SHA retornado por `git ls-remote`.

Ele usa:

```bash
git ls-remote \
    https://github.com/CachyOS/linux \
    "refs/tags/${UPSTREAM_TAG}^{}"
```

A forma `^{}` solicita o objeto para o qual a tag aponta, permitindo usar o commit real do código-fonte.

Depois o script compara:

```text
commit esperado
      ==
commit efetivamente baixado
```

Se não forem iguais, o processo para antes do build.

## Release do RPM

O projeto precisa distinguir o build x86-64-v2 do pacote upstream sem assumir que o release original continuará sendo sempre o mesmo número.

Por isso, em vez de procurar uma string fixa como `cachyos2`, o script preserva a base e insere `.v2` antes das macros RPM.

Exemplo:

```text
cachyos1%{?_lto_args:.lto}%{?dist}
                    ↓
cachyos1.v2%{?_lto_args:.lto}%{?dist}
```

Isso evita quebrar quando a revisão upstream mudar de `cachyos2` para `cachyos1`, `cachyos3` ou outra base.

## Por que o `config` não é validado no meta-pacote

Uma tentativa anterior de validação procurava um arquivo `config` diretamente dentro do RPM principal `kernel-cachyos`.

Essa premissa não é uma propriedade segura do empacotamento. O kernel é dividido em subpacotes e o conteúdo relevante para configuração pode estar em outro pacote.

Por isso, o fluxo atual não bloqueia um build válido com uma checagem de caminho inventada para o meta-pacote.

A validação final se concentra no que realmente determina sucesso do objetivo do script:

- `rpmbuild` terminou com sucesso;
- RPMs foram realmente gerados;
- as arquiteturas são aceitáveis;
- os pacotes esperados existem;
- a instalação foi concluída pelo DNF.

## Atualização

A mesma rotina é usada para acompanhar uma revisão mais nova do `kernel-cachyos`.

O script volta ao repositório oficial de empacotamento, usa o `origin/HEAD` atual, lê novamente o SPEC e descobre a versão upstream daquele momento.

O processo fica assim:

```text
novo commit do packaging
          ↓
novo SPEC
          ↓
novo Source0
          ↓
novo tag
          ↓
novo commit
          ↓
novo RPM x86-64-v2
```

Ver detalhes em [`docs/UPDATE.md`](docs/UPDATE.md).

## Verificação após a instalação

Depois de reiniciar no novo kernel, confira:

```bash
uname -r
```

Também é útil verificar o kernel completo com:

```bash
fastfetch
```

O nome exato do release varia conforme a versão upstream construída.

## Fallback e recuperação

Como o script não remove kernels antigos, mantenha pelo menos um kernel conhecido como funcional antes de testar o novo build.

Se o kernel novo apresentar problemas, selecione o kernel anterior no menu de boot do Fedora.

Para diagnóstico, consulte [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

## Desempenho

Este projeto é uma adaptação de compatibilidade/empacotamento, não uma promessa de ganho universal de desempenho.

Resultados de FPS, latência, tempo de inicialização ou responsividade dependem do hardware, carga, driver gráfico, jogo, configuração e versão do kernel.

Benchmarks devem ser comparados sob condições controladas.

## Estrutura do repositório

```text
.
├── README.md
├── build-kernel-cachyos-v2.sh
└── docs/
    ├── BUILD.md
    ├── UPDATE.md
    ├── TECHNICAL.md
    └── TROUBLESHOOTING.md
```

## Documentação complementar

- [`docs/BUILD.md`](docs/BUILD.md): passo a passo do build e leitura dos artefatos.
- [`docs/UPDATE.md`](docs/UPDATE.md): atualização para uma revisão nova do CachyOS.
- [`docs/TECHNICAL.md`](docs/TECHNICAL.md): decisões técnicas e motivos das proteções do script.
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md): diagnóstico dos erros mais prováveis.

## Créditos

O projeto utiliza diretamente o trabalho do CachyOS e do Linux upstream. Os repositórios oficiais continuam sendo a referência para código-fonte, empacotamento e alterações do kernel.

## Licenciamento
o projeto usa a licença GNU General Public License v3.0
