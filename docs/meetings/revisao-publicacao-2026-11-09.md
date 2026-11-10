# Revisão para publicação — 09/11/2026

**Resultado: os quatro recursos estão implementados e integrados, mas não há evidência suficiente para declarar 100% de paridade ou homologação para produção.** A revisão encontrou e corrigiu uma falha que impediria levar o AEC3 a um checkout novo e três contratos de teste desatualizados. A publicação não foi realizada.

## Comparação com o Fluid Voice

Referência local: `FluidVoice-main/Sources/Fluid/Services/Meeting`, com consulta a `MeetingCaptureEngine.swift`, `LiveTranscription/MeetingLiveTranscriptionCoordinator.swift` e ao inventário de persistência, diarização e resumo. A integração anterior e suas revisões estão em [modelos locais e AEC](paridade-local-live-aec-2026-11-07.md).

| Capacidade | OpenLess e adaptação | O que ainda exige aceite |
| --- | --- | --- |
| Reuniões online/presenciais | Microfone + aplicação selecionada via ScreenCaptureKit, ou microfone presencial; blocos WAV e recuperação; IPC e tela React/Tauri | Permissões, dispositivos e interrupções numa captura real |
| Transcrição e falantes | FluidAudio real com Parakeet v3/Nemotron locais ou ElevenLabs com tempos; editor e união manual | Precisão e alternância de duas ou mais vozes numa reunião conhecida; identidades são independentes por trilha |
| Resumo, decisões e tarefas | Canal independente, transporte Gemini nativo e respostas estruturadas com proveniência; sem dependência do Fluid Intelligence privado | Chamada com o canal/modelo/chave do usuário |
| Importação de áudio/vídeo | AVFoundation/ExtAudioFile; alternativa FFmpeg preexistente quando necessária; sete testes reais passaram | Formatos do usuário no aplicativo; FFmpeg não é incluído nem instalado |
| Legendas | EOU em inglês e Parakeet em português/espanhol/francês/alemão; fila limitada e rascunhos por fonte | Latência e comportamento numa captura real; na referência consultada o coordenador aceita somente inglês |
| Eco | Mesmo AEC3 fixado, alinhamento de relógio, microfone bruto preservado e fallback; dylib separada macOS 15+ | Alto-falantes e fala simultânea numa chamada real; não há benchmark comparativo |
| Revisão/exportação | Player por bloco, edição/união de falantes, JSON/Markdown/TXT, resumo invalidado após edição | Fluxo visual completo e reabertura no aplicativo |

Não depende de Google Meet. O modo online captura a aplicação selecionada, não todo o áudio global automaticamente. Reuniões nativas exigem macOS 14+, AEC macOS 15+, e os modelos locais exigem Apple Silicon. As legendas locais exigem pelo menos 8 GB. Outros hosts não receberam paridade de captura.

## Correções desta revisão

1. `.gitignore` excluía `vendor/webrtc-aec3/Artifacts`. O binário universal, header e Info.plist eram necessários ao build local, mas ficariam ausentes no commit/checkout. Adicionada exceção somente para a pasta fixada do fornecedor.
2. Adicionado `scripts/meeting-vendor-contract.test.mjs`: confere SHA-256 dos três arquivos contra o manifesto upstream e verifica com `git check-ignore --no-index` que são versionáveis. A listagem de arquivos novos do Git agora inclui os três.
3. Contrato de empacotamento macOS atualizado para a mensagem portuguesa, mantendo a proteção contra recursos MLX retirados.
4. Contrato de versão deixou de exigir uma beta antiga: valida o formato e a igualdade exata entre package.json, locks, Cargo e Tauri, preservando caixa/sufixo.
5. Contrato do repositório passa a exigir `flavioacv/openless` nos endpoints do atualizador, em vez do upstream.

Não foi alterado o código de execução do Meeting nesta revisão. O aplicativo de teste gerado em 08/11 continua sendo o pacote disponível; não se trata de uma nova release.

## Verificações executadas novamente

| Verificação | Evidência |
| --- | --- |
| Testes TypeScript | 64 arquivos aprovados, executados com `node --import tsx` |
| Contratos JavaScript existentes | 89 arquivos aprovados |
| Novo contrato do fornecedor Meeting | Aprovado: três hashes e exclusão Git conferidos |
| Core de reuniões | 32 testes aprovados: 13 documentos, 9 processamento, 4 trilhas e 6 contratos |
| Ponte nativa Swift | 14 XCTest aprovados sem falhas, incluindo inferência e legendas com pesos reais e áudio português |
| Importação nativa/alternativa local | 7 testes aprovados, incluindo MOV PCM/AAC e AAC isolado |
| Gemini | 17 testes aprovados sem chamadas pagas |
| AEC3 | Regressão sintética aprovada através da dylib real; não representa uma chamada real |
| Preparação de release e aliases | Testes existentes aprovados |
| Whitespace do diff | `git diff --check` aprovado |

O lançador CLI do tsx tenta abrir um socket negado pelo ambiente; os 64 testes foram executados diretamente pelo carregador `node --import tsx`, sem alterar a proteção do ambiente. O teste HTTP de loopback explicitamente ignorado não integra o total aprovado. Os testes de download usam URLSession com respostas HTTP em memória; os modelos de inferência são reais.

Logs temporários: `/private/tmp/openless-review-{typescript,mjs-final,core,native,media,gemini,aec}-20261109.log`. O novo teste do fornecedor foi executado separadamente depois dos 89 contratos existentes. O build completo e a assinatura ad hoc anteriores estão documentados na [entrega de 08/11](correcoes-finais-2026-11-08.md).

## Publicação: impedimentos concretos

- O usuário autorizou commit e PR após a revisão. A tentativa de staging falhou com `Unable to create .../.git/index.lock: Operation not permitted`. O perfil de permissões desta sessão permite apenas leitura de `.git`. Não foram criados commit, push, PR ou tags e não foi realizado merge. Não há autorização para contornar esse bloqueio por outro processo.
- Não foi gerado um DMG nesta sessão: serviços de montagem/criação de imagem do macOS estavam bloqueados na entrega anterior. A correção de arte não equivale a instalador produzido e instalado.
- Captura/permissões/interface, download público pelo aplicativo, APIs reais e qualidade numa reunião precisam de aceite. Não há base para publicar como versão estável 100% homologada.
- A release pública consultada no GitHub continua sendo [v2.0.2-tauri](https://github.com/flavioacv/openless/releases/tag/v2.0.2-tauri); os manifests locais também estão em 2.0.2. Nenhuma versão antiga foi sobrescrita.

## Continuidade da entrega autorizada

O [texto do PR](../releases/meeting-pr-draft-2026-11-09.md) e as [notas de release](../releases/meetings-release-notes-draft.md) estão preparados para revisão. A próxima versão proposta é 2.1.0, com tag `v2.1.0-tauri`; ela não foi gravada nos manifests nem criada no Git.

Após liberar escrita Git nesta sessão, concluir o aceite e conferir a origem exata dos pacotes: sincronizar a versão pelo `scripts/prepare-fork-release.mjs`, commitar na branch de trabalho e enviar a branch; abrir PR para `main`; aguardar aprovação expressa antes de merge; construir pacotes do commit aprovado usando os workflows existentes; conferir assinaturas, hashes e arquivos do atualizador; só então publicar o draft para download. O fluxo existente exige CI aprovado no commit exato e impede publicar pacotes incompletos.
