# Reuniões no OpenLess

Integração na branch `feat/meeting-recording`, com build nativo completo e testes dos modelos reais em português aprovados. A validação das permissões e da captura no Mac do usuário continua necessária antes de uso em produção.

- [Revisão para publicação — 09/11](revisao-publicacao-2026-11-09.md): comparação, correções dos contratos e impedimentos para release.
- [Correções e entrega atual — 08/11](correcoes-finais-2026-11-08.md): mídia, download, cancelamento e limites de homologação.
- [Como testar](como-testar.md): configuração de canais e roteiro de gravação/importação.
- [Entrega para testes](entrega-para-testes-2026-11-07.md): evidências atuais, aplicativo e limites do ambiente.
- [Kanban](../../reunioes.kanban): progresso e pendências.
- [Levantamento](levantamento-2026-11-07.md): comparação e referência FluidVoice.
- [Validação da integração](validacao-integracao-2026-11-07.md): verificações e limites atuais.
- [Modelos locais, legendas e eco](paridade-local-live-aec-2026-11-07.md): integração autorizada do FluidAudio e diferenças em relação à referência.
- [Briefing](handoff-2026-11-07.md): histórico; as restrições de escrita descritas ali são da sessão anterior.

## Código integrado

O core possui documentos versionados, armazenamento atômico, revisões, falantes, segmentos temporais e resumo estruturado com decisões, tarefas e referências à transcrição. Edições invalidam o resumo anterior sem apagá-lo.

A tela de reuniões está ligada aos comandos Tauri: gravação, importação, transcrição, edição de falantes/texto, reprodução por bloco, recuperação e exportação JSON/Markdown/TXT. Os arquivos de reunião são independentes do histórico de ditado.

No macOS 14+, uma ponte Swift usa AVFoundation e ScreenCaptureKit para microfone e áudio da aplicação em trilhas separadas. Importação de áudio e extração de áudio de vídeo alimentam o mesmo formato PCM mono 16 kHz, com blocos de até 60 segundos e manifesto de recuperação. O original importado é preservado. Cancelamento e exclusão mútua com outras sessões de voz estão integrados.

A transcrição com falantes oferece Parakeet v3 + Nemotron locais em Apple Silicon, após download explícito na tela, ou o canal ElevenLabs escolhido. Os arquivos são verificados contra as revisões publicadas; o caminho local não usa credenciais nem envia áudio ao provedor. Resumos usam o canal de IA escolhido (ou o atual), com transporte nativo Gemini e validação de referências, decisões e tarefas. Gravação e importação não iniciam upload automaticamente.

Legendas locais opcionais aceitam português, espanhol, francês e alemão com Parakeet v3, em janelas limitadas a 12 segundos e atualização a cada três segundos de áudio. A última parte fica provisória para reduzir cortes e repetição de palavras. Inglês usa Parakeet EOU. Ambos exigem Apple Silicon com pelo menos 8 GB. São rascunhos por fonte; a transcrição final com falantes é solicitada separadamente. Cancelamento acústico de eco usa o WebRTC AEC3 da referência em gravação de aplicação + microfone no macOS 15+. O microfone original é preservado; problemas de sincronismo/processamento mantêm o áudio bruto e exibem aviso. Há união manual dos rótulos de falantes na interface.

## Pendências

- Aplicativo Tauri de teste gerado e assinatura local verificada: `openless-all/app/src-tauri/target/debug/bundle/macos/OpenLess.app`. `cargo check`, `cargo build` e `tauri build --debug --bundles app` completos passaram usando as dependências Swift reais preparadas localmente. A resolução remota de pacotes pelo processo restrito não foi validada; o instalador DMG de distribuição não foi gerado.
- Testes com reunião real, permissões, microfone + aplicação, troca de dispositivos e APIs de IA.
- Validação visual da interface e precisão em português, sobreposição de fala e cancelamento durante uso real.
- Não há associação biométrica entre falantes de trilhas diferentes. Usar fones ajuda a conferir as fontes no primeiro teste; o AEC exige validação com os alto-falantes reais.
- FluidAudio e AEC3 foram integrados com autorização do usuário. Os três modelos foram baixados por HTTPS e tiveram hashes verificados. Parakeet/Nemotron e legendas em português passaram com áudio público real. O instalador de modelos passou em testes de download/cancelamento/retomada com HTTP controlado; conexão pública dentro do aplicativo, APIs pagas e a comparação de desempenho com FluidVoice ainda exigem teste no Mac do usuário. Fluid Intelligence é privado; resumos usam o LLM separado.
- Captura/importação nativas desta etapa são macOS; não foi entregue paridade com outros hosts.
- Exportação implementada; política de exclusão/retenção ainda requer definição.
- Commit e PR autorizados em 09/11, condicionados à revisão. Staging bloqueado por permissão de escrita em `.git`; sem commit, push, PR, merge ou nova release.

Foram adicionados FluidAudio via SwiftPM, suas dependências transitivas e o componente AEC3 da referência, com revisões e avisos de licença. Não considerar presença do código ou testes isolados como aceite dos quatro recursos no aplicativo.
