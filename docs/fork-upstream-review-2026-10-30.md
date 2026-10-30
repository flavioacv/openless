# Revisão do upstream e atualização do fork — 30/10/2026

## Referências verificadas

- Fork: `flavioacv/openless`, branch de origem `beta`, HEAD `4670509b`.
- Oficial Stable (`main`): `f0744e10`, ancestral do fork. Nenhuma novidade Stable posterior na consulta.
- Oficial Beta: `3a0bb311` (29/10/2026).
- Comparação: https://github.com/Open-Less/openless/compare/f0744e10...3a0bb311
- O fork possui três commits próprios: `1126febc` (português), `ff5f78e9` (Opus e inserção rica) e `4670509b` (mensagens). Eles alteram 41 arquivos; nenhum desses arquivos foi modificado nesta integração.

## Incorporações selecionadas

Aplicados os patches completos, sem merge amplo nem atualização de dependências:

- [ace8c3a5 / #1245](https://github.com/Open-Less/openless/commit/ace8c3a5fb921e5ac90b6a1b2ff4ab788259bdbb): o instalador local macOS compara o designated requirement antes de resetar permissões TCC. Assinatura estável preserva autorizações; mudança da assinatura continua exigindo reset.
- [d37394ec / #1257](https://github.com/Open-Less/openless/commit/d37394ec99d75ca29c07841079ce4b362147968c): TextStream preserva o texto autoritativo quando o reconhecedor revisa um prefixo, em vez de abortar a transcrição. Inclui teste de regressão do upstream.

## Melhorias relevantes para outra integração

- `a689f204` (#1246): Gemini, normalização de URL, modelos e Thinking. Altera Core, interfaces e traduções; requer adaptação ao português e às mudanças próprias de provider_service.
- `0212024a`, `e4457efd`, `1328820b` e ajustes de CI: afinidade de thread e handles da cápsula. Avaliar juntos com testes nativos Windows/macOS; o fork possui mudanças próprias na cápsula.
- `bddad88d`: diagnóstico de decodificação offline Sherpa.
- `caa1b204`, `ee0e3cd4`: processamento de áudio e cancelamento opcional de eco. Escopo amplo, validação com microfone/dispositivos necessária.
- `f71ffd54` e correções associadas: sincronização de preferências e contexto do cursor; sobreposição com adaptações locais.
- `ac0b159d`: teclado Android, aprendizado e digitação em inglês.
- Mudanças Linux: logs, ditado e remoção de Less Computer. Não incorporadas automaticamente porque incluem remoção de funcionalidade.
- `60f67a9b`: build/testes iOS e muitas alterações em recursos/licenças. Mantidos os arquivos iOS locais.
- `1fe6ad50` (#1277): updater oficial passou a CDN. Não incorporado: o fork conserva o protocolo GitHub Releases já existente, sem depender da infraestrutura do oficial.
- Mudanças de versão e distribuição automática Linux/Harmony não foram incorporadas; não constituem pré-requisito para o updater do fork.

## Atualizador do fork

Os endpoints Stable, descoberta Beta via Atom, manifestos Beta, allowlist Android, links de download/ajuda/notas e padrão do gerador de manifestos agora apontam para `flavioacv/openless`. O workflow Android usa `github.repository`, como o desktop já usava. O fallback FastGit existente foi preservado e também aponta para o fork.

A notificação já existe em `AutoUpdateGate.tsx`: consulta após 4 segundos e a cada 60 minutos, respeitando `autoUpdateCheck`. Desktop mostra diálogo; Android mantém seu comportamento existente de download e abertura do instalador. Não foi criado um segundo mecanismo de notificação.

## Build e requisitos de publicação

A esteira é GitHub Actions: `release-tauri.yml` (macOS/Windows) e `android-apk.yml` (Android). Tags `v<X.Y.Z>-tauri` e `v<X.Y.Z>-Beta.<N>-tauri` geram assets e manifestos por plataforma/canal em um draft compartilhado. O administrador verifica ambos os workflows antes de publicar. Linux possui workflow próprio e não oferece updater dentro do app; iOS não usa este fluxo Tauri.

A consulta pública à API de releases do fork retornou lista vazia nesta data. Assim, trocar os endpoints não basta para receber uma nova versão até publicar uma release com os respectivos manifestos e arquivos assinados.

Antes da primeira publicação:

1. Configurar um par de assinatura Tauri próprio. A chave pública atualmente presente ainda é a herdada do oficial; não há comprovação de posse da chave privada correspondente. Substituir de forma coordenada `plugins.updater.pubkey` em `tauri.conf.json` e `UPDATER_PUBKEY_B64` em `android/updater_logic.rs`, e configurar os secrets `TAURI_SIGNING_PRIVATE_KEY` e `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` do fork. Não publicar com par divergente.
2. Para macOS assinado/notarizado, configurar os secrets Apple previstos no workflow. Conferir também a assinatura Android e os secrets exigidos pela esteira antes de disparar a release.
3. Incrementar e sincronizar as cinco versões descritas em `RELEASING.md`; metadados de build não aumentam a precedência SemVer.
4. Executar CI e aceitação dos dispositivos, criar a tag somente por ação do administrador e publicar o draft após verificar assinaturas, URLs e manifestos.
5. Instalar manualmente uma versão do fork com os novos endpoints e a chave própria. Binários antigos continuarão consultando o oficial; editar o código não migra aplicativos já instalados.

Cloudflare não é necessário para o protocolo escolhido. Nenhuma conta, secret, tag ou release foi criada ou alterada. Não foi feito commit, push ou PR.

## Limites da análise

A consulta obrigatória de impacto ao MCP foi executada para cada arquivo existente alterado; o grafo não encontrou entidades do projeto. As referências foram verificadas por pesquisa textual, histórico e diffs. Testes automatizados não substituem reinstalação macOS real nem atualização com assets e assinaturas de produção.
