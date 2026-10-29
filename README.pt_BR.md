# kof-main-sync

Mantém um checkout local do [`main` do Kof](https://github.com/KofLang/Kof4j), um fork pessoal existente e uma instalação Linux validada em sincronia.

[Read in English](README.md)

## O que ele faz

O `kof-main-sync` executa três fases independentes:

1. Avança por fast-forward um checkout local limpo de `main` a partir de `upstream/main`, mantendo código e documentação atuais para consulta por outros projetos.
2. Avança um fork pessoal existente quando sua `main` for ancestral do commit sincronizado.
3. Instala uma release Linux oficial somente quando sua tag aponta para o mesmo commit de `main` e o checksum e a estrutura do pacote forem válidos.

Com `INSTALL_KOF=true`, cada execução primeiro restaura a instalação anterior registrada se o compilador ativo estiver em `SKIP_KOF_VERSIONS`. A recuperação usa o lock compartilhado da instalação e ocorre antes de verificar a árvore de trabalho ou acessar os remotos Git. Assim, checkout sujo ou falha de rede não impedem a recuperação.

Falha na release nunca reverte a documentação atualizada. Não existe fallback de compilação local: se a CI de release do Kof não publicar o artefato, o compilador atualmente instalado continua ativo.

A ferramenta nunca usa hard reset, rebase, merge commit, force push ou descarte automático de commits.

## Sistemas suportados e requisitos

Os ambientes inicialmente suportados são Debian, Ubuntu e WSL2. Comandos necessários:

```text
bash git gh flock crontab curl tar sha256sum
```

Autentique o GitHub CLI antes da instalação:

```bash
gh auth login
```

O instalador valida dependências e o cron, mas nunca executa `sudo`, instala pacotes, inicia serviços ou cria um fork no GitHub.

## Instalação

O método suportado permite revisar o código antes da execução:

```bash
git clone https://github.com/renanfranca/kof-main-sync.git \
  ~/projects/kof-main-sync
cd ~/projects/kof-main-sync
./install.sh --dry-run
./install.sh
```

Por padrão, ele:

- gerencia o Kof em `$HOME/projects/kof`;
- usa `KofLang/Kof4j` como `upstream`;
- detecta `$USUARIO_GITHUB/Kof4j` apenas quando já for um fork do upstream;
- instala o comando em `$HOME/.local/bin/kof-main-sync`;
- grava configuração e estado seguindo XDG;
- agenda uma execução a cada cinco minutos.

O instalador executa inicialmente apenas um dry-run. A primeira sincronização real ocorrerá pelo cron ou com:

```bash
kof-main-sync run
```

### Opções do instalador

```text
--repo-dir <caminho>    usa outro checkout do Kof
--origin <owner/repo>   usa um fork existente explícito
--no-origin             desabilita sincronização do fork
--no-kof-install        atualiza código/docs sem alterar o Kof instalado
--interval <minutos>    intervalo do cron entre 1 e 59
--dry-run               valida sem alterar arquivos, remotos ou cron
```

Se o checkout não existir, o instalador clona o upstream e configura os remotos. Remotos existentes são validados e nunca substituídos silenciosamente.

## Comandos

```bash
kof-main-sync run
kof-main-sync run --dry-run
kof-main-sync status
kof-main-sync logs
kof-main-sync logs --follow
kof-main-sync rollback
kof-main-sync install
kof-main-sync uninstall
```

`install` e `uninstall` gerenciam somente a entrada marcada do cron. O `uninstall.sh` do repositório também remove o comando instalado e a configuração, preservando checkouts, distribuições e logs do Kof.

Códigos de saída:

| Código | Significado |
|---:|---|
| `0` | Todas as fases habilitadas funcionaram ou já estavam atualizadas |
| `10` | Uma fase foi pulada com segurança, como checkout sujo, release pendente ou versão ignorada |
| `11` | Outra execução possui o lock |
| `20+` | Erro de configuração, rede, autenticação, integridade ou instalação |

## Configuração e caminhos

Os padrões seguem a especificação XDG:

```text
Comando:      $HOME/.local/bin/kof-main-sync
Configuração: ${XDG_CONFIG_HOME:-$HOME/.config}/kof-main-sync/config
Estado/log:   ${XDG_STATE_HOME:-$HOME/.local/state}/kof-main-sync/
Instalações:  ${XDG_DATA_HOME:-$HOME/.local/share}/kof/
Comando Kof:  $HOME/.local/bin/kof
```

A configuração é interpretada como dados e nunca carregada como código shell. Consulte [`config/config.example`](config/config.example).

Para ignorar uma release problemática do Kof, edite a configuração existente:

```ini
SKIP_KOF_VERSIONS=0.6.7
```

Aceita várias versões exatas separadas por vírgulas, por exemplo `SKIP_KOF_VERSIONS=0.6.7, 0.6.5`, com espaços opcionais ao redor de cada entrada. A versão deve começar por um dígito e conter apenas letras ASCII, dígitos, pontos, sublinhados ou hífens. Entradas vazias entre vírgulas, expressões shell e outros valores inválidos geram diagnóstico e código `20`, sem alterar a instalação. Chave ausente ou valor vazio mantém o comportamento existente. A reinstalação preserva a lista configurada.

Ignorar `0.6.7` não ignora `0.6.70` nem uma futura `0.6.8`. Uma versão posterior permitida continua sendo instalada automaticamente quando passa nas verificações existentes de release, checksum, pacote e correspondência entre tag e commit. O bloqueio ocorre antes de consultar tags/releases, baixar arquivos ou ativar distribuições já presentes no disco; uma release ignorada retorna `10`. O `status` exibe a lista e alerta quando o compilador realmente ativo está ignorado. Bloqueios e recuperações são registrados no log.

Entrada marcada do crontab:

```cron
*/5 * * * * /home/<usuario>/.local/bin/kof-main-sync run >/dev/null 2>&1 # kof-main-sync
```

Todas as outras entradas são preservadas byte por byte.

## Validação da release e rollback

Para a versão `<versão>`, a ferramenta exige a tag:

```text
kof-<versão>-linux-x86_64
```

A tag deve resolver para o commit sincronizado. A release deve conter o arquivo correspondente e `SHA256SUMS`; checksum, caminhos internos, layout, JDK embutido, `kof version` e `kof info` precisam passar antes da ativação.

A ativação substitui somente o symlink `~/.local/bin/kof`, usando rename atômico. Distribuições anteriores permanecem no disco. Para restaurar a anterior:

```bash
kof-main-sync rollback
```

Tanto a recuperação automática quanto `rollback` conferem a versão real do compilador anterior contra `PREVIOUS_VERSION` de `installed.state`, executam `version` e `info` e exigem o JDK embutido. Uma instalação anterior bloqueada, ausente, divergente ou com falha gera diagnóstico e código `20`, preservando o symlink ativo e o estado da instalação. A ferramenta não procura nem baixa outra candidata para recuperação. A distribuição restaurada passa a ativa e a substituída fica registrada como anterior; `rollback` recusa reativá-la enquanto estiver ignorada.

`run`, `run --dry-run` e `rollback` compartilham o lock e retornam `11` quando ele está ocupado. O instalador também usa esse lock ao substituir o executável e a configuração. `run --dry-run` mostra a recuperação e os bloqueios previstos sem alterar o symlink do Kof nem `installed.state`. Ele pode atualizar referências locais dos remotos e logs. `INSTALL_KOF=false` desabilita recuperação automática e instalação de releases; um `rollback` explícito continua respeitando a lista.

Versões antigas nunca são apagadas automaticamente. Depois de confirmar que uma versão não será necessária para rollback, remova manualmente apenas seu diretório específico em `~/.local/share/kof/`.

## Paradas seguras e recuperação

A atualização do checkout é pulada quando:

- existem alterações rastreadas ou não rastreadas;
- a branch atual não é `main` ou o HEAD está detached;
- existe merge, rebase, cherry-pick, revert ou bisect em andamento;
- a `main` local possui commits exclusivos ou diverge do upstream.

O fork é pulado quando sua `main` estiver à frente ou divergente. Resolva essas condições Git manualmente; a ferramenta tentará novamente na próxima execução.

O fetch aceita histórico reescrito nas referências locais dos remotos (`upstream/main` e `origin/main`). A branch de trabalho e o fork continuam avançando somente por fast-forward; divergências exigem recuperação manual. A sincronização automática nunca executa reset da branch de trabalho nem force push do fork.

Uma release indisponível é normal enquanto a CI do Kof está executando. Documentação e fork podem avançar enquanto o compilador instalado permanece na última versão validada.

Use `kof-main-sync status` e `kof-main-sync logs` para diagnóstico. O log gira ao atingir 5 MiB, mantém cinco arquivos anteriores e nunca inclui tokens do GitHub.

## WSL2

O cron funciona apenas enquanto a distribuição WSL2 estiver ativa. Agendamentos perdidos não são reproduzidos, mas a próxima execução converge diretamente para o estado seguro mais recente. Com systemd habilitado, verifique:

```bash
systemctl is-active cron
```

## Desenvolvimento

Execute a suíte isolada:

```bash
tests/run.sh
```

Ela usa HOME, repositórios Git, pacotes e comandos temporários; não toca no checkout, fork, crontab ou instalação reais.

## Licença

Apache License 2.0. Consulte [`LICENSE`](LICENSE).
