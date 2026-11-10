# Levantamento: reuniões no OpenLess

Data: 07/11/2026. Análise das cópias locais do OpenLess e FluidVoice.

## 1. Resultado executivo

A integração é viável, mas não consiste em ativar uma configuração existente. O OpenLess fornece captura de microfone, normalização de áudio, ASR, credenciais, transporte LLM, eventos e armazenamento. Faltam o domínio de reuniões, captura dedicada do áudio da aplicação, transcrição com tempos/falantes, persistência de sessões longas e fluxo de importação de mídia.

Recomendação técnica: adicionar um domínio de reuniões no openless-core e adaptadores nativos de captura/decodificação/inferência nos hosts. Começar pelo macOS, pela proximidade com a implementação analisada; expansão a outras plataformas deve ser uma entrega própria. Essa ordem é uma proposta, não uma decisão de produto já aprovada.

O levantamento não altera código, não seleciona definitivamente novas dependências e não comprova qualidade ou desempenho com áudio real.

## 2. Mapa dos quatro requisitos

| Requisito | Referência no FluidVoice | Base existente no OpenLess | Implementação necessária |
| --- | --- | --- | --- |
| Gravação de reuniões | MeetingCaptureEngine, MeetingAudioChunkWriter, MeetingSessionCoordinator, MeetingSessionStore | recorder.rs, AudioRecorder, AudioProcessor, VoiceSessionGate | Captura de aplicação + microfone em trilhas separadas, linha do tempo comum, gravação durável por blocos, recuperação e tela de reuniões |
| Identificação de falantes | MeetingParakeetNemotronBackend, MeetingProductionParakeetNemotronRuntime, MeetingSpeakerVoiceMatcher, MeetingTranscriptAssembler | ASR local/nuvem, ModelStore, ModelRuntimeAdapter | Motor de diarização, tempos dos segmentos, associação texto/falante, identidade estável na sessão e correção manual |
| Resumos, decisões e tarefas | MeetingSummaryController, MeetingSummaryProvider, MeetingSummaryView | polish.rs, llm_protocol.rs, provider_resolution.rs, credenciais e transportes | Serviço de resumo dedicado, resultados separados, persistência e invalidação por revisão; estrutura de tarefas caso se deseje gestão além de Markdown |
| Importação de áudio/vídeo | FileTranscriptionService, SpeakerDiarizationService | ExternalAudioRecorder, normalização PCM e retranscrição de gravações existentes | Seleção/inspeção de mídia, extração e decodificação em blocos, cópia gerenciada, cancelamento e uso do mesmo processamento das reuniões |

## 3. Gravação: o que levar como referência

O FluidVoice distingue reunião online de presencial. Na online, grava applicationAudio e microphone; na presencial, apenas microphone. A captura usa ScreenCaptureKit e caminhos de processamento de voz, com proteção contra eco, monitoramento de interrupções e mudança de dispositivos. Os blocos têm duração padrão de 60 segundos.

Implementar no OpenLess:

- Fonte online explícita: aplicação selecionada e microfone. Fonte presencial: microfone.
- Gravação em disco durante a captura. O ASR e o resumo não devem interromper a preservação do áudio quando falharem.
- Metadados por bloco: trilha, formato, início/fim, índice, estado de finalização e integridade. Relacionar relógios de captura à linha do tempo da reunião; não concatenar sem contabilizar pausas, deriva e descontinuidades.
- Filas limitadas entre callback de áudio e escrita/processamento. Informar perda ou lacuna; não classificar captura parcial como completa.
- Interrupções: permissão revogada, aplicação encerrada, microfone desconectado, suspensão, disco cheio e encerramento inesperado.
- Coordenação com VoiceSessionGate e RuntimeActivityGate para evitar conflito com ditado, QA, edição por voz, restauração de dados e modelos locais. A regra de concorrência precisa ser explícita; a sugestão inicial é exclusividade dos recursos conflitantes.
- Eco: preservar trilhas independentes e implementar AEC/sinalização de trechos incertos. Fala duplicada entre alto-falante e microfone não deve virar um segundo participante.

O recorder.rs atual é uma fonte de reaproveitamento da captura de microfone e de tratamento de filas; não substitui o capturador de áudio da aplicação. ExternalAudioRecorder recebe PCM canônico de uma sessão de ditado; não é, por si só, uma API de importação ou de múltiplas trilhas.

## 4. Identificação de falantes: principal mudança de contrato

Em ports.rs, TranscriptOutput contém somente text e duration_ms. DictationSession, em types.rs, também não representa uma sequência de segmentos com falantes. Assim, reutilizar o ASR sem um novo resultado perde informações necessárias à diarização.

Proposta: manter o contrato de ditado e acrescentar um resultado próprio para reuniões, com:

- IDs de reunião, tentativa de processamento, trilha e segmento.
- Início/fim relativos à reunião, texto e precisão temporal real fornecida pelo motor.
- speakerId opcional; estado sem atribuição, sobreposição ou incerteza quando aplicável.
- Origem e versão do modelo; indicação de transcrição provisória/final e cobertura incompleta.
- Texto original, revisão e correções do usuário preservadas.

Separar três operações: detectar quando há fala, reconhecer o texto e agrupar intervalos pela voz. Alinhar os resultados pelos tempos. Não fabricar tempos por palavra quando o motor fornece apenas uma frase.

O FluidVoice usa Parakeet para ASR e Nemotron/Sortformer para diarização no backend principal. O descriptor declara oito slots de falantes por época de análise, não oito pessoas garantidas por reunião inteira. O matching de voz é conservador e exige cuidado na união entre blocos/épocas. O backend local principal depende de Apple Silicon.

Identificação aqui significa “Falante 1”, “Falante 2” e associação de trechos da mesma voz; não é reconhecimento automático do nome civil. Permitir nomear, unir e corrigir falantes dentro da sessão. Não propor uma base biométrica global para atender este escopo.

No OpenLess, o adaptador ElevenLabs pede timestamps_granularity=none e reduz a resposta a texto. Portanto, a presença do provedor não significa que a aplicação já aproveita diarização ou tempos. O Whisper solicita verbose_json em rotas compatíveis, mas o contrato comum ainda não transporta segmentos de reuniões.

Escolha de execução ainda pendente: adaptador local no macOS inspirado no FluidAudio versus adaptador de provedor que entregue diarização. A disponibilidade local atual do Qwen/Whisper no OpenLess não fornece automaticamente diarização. Novos modelos, pacotes e seus requisitos devem ser avaliados e aprovados antes da implementação.

## 5. Resumos, decisões e tarefas

No FluidVoice, MeetingSummaryKind tem executive, detailed, actions, decisions, participants, topics e custom. O caminho remoto usa provedor/modelo configurado; o local depende da disponibilidade do componente privado. O prompt orienta a não inventar fatos, responsáveis ou prazos e a distinguir decisões de sugestões. Os resultados salvos têm hashes do conteúdo/configuração e versão do prompt.

Limitação relevante: a implementação examinada retorna Markdown. A lista de ações não equivale a um gerenciador de tarefas estruturado com status, atribuição e acompanhamento. O caminho remoto também impõe limite de 512.000 bytes da transcrição em uma requisição; o local declara 96.000 bytes. Esses limites não equivalem à janela de tokens de qualquer modelo.

No OpenLess, reaproveitar resolução de provedor, credenciais, transporte e parsing de protocolos. Criar uma operação de resumo própria: os prompts de polish/QA podem inserir objetivos inadequados à elaboração de ata. A assinatura answer_chat_streaming demonstra transporte existente, mas não comprova um serviço pronto de resumo arbitrário sem adaptação.

Proposta para os três resultados solicitados:

- Resumo legível e editável, separado da transcrição original.
- Decisões explicitamente afirmadas, com referência aos segmentos de origem quando disponível.
- Tarefas com descrição, responsável e prazo apenas quando constarem na transcrição; ausentes permanecem sem definição. Gestão de status é um possível complemento, não requisito assumido.
- Persistir modelo, provedor, versão do prompt e revisão da transcrição; após edição da fonte, indicar que o resultado precisa ser regenerado.
- Tratar a transcrição como dados, não como comandos de sistema. Falha de IA não pode apagar áudio, transcrição ou resumo anterior válido.
- Para reuniões longas, segmentar conforme contexto do modelo e consolidar com referências à fonte, sem truncamento silencioso. Essa consolidação precisa de avaliação de omissões e duplicatas.

Não depender do Fluid Intelligence privado. O OpenLess pode usar provedores já configurados; resumo offline só deve ser anunciado quando houver um runtime local validado para essa operação.

## 6. Importação de áudio e vídeo

O FileTranscriptionService anuncia WAV, MP3, M4A, OGG, OPUS, MP4, MOV e outros formatos decodificáveis pelo sistema. Faz processamento por blocos e registra resultado/histórico. Entretanto, o código desvia explicitamente de speaker labeling para contêineres de vídeo. A lista de extensões também não garante que todo codec dentro de um contêiner seja decodificado.

Para atender os quatro requisitos em conjunto no OpenLess:

1. Inspecionar o arquivo real, duração, codecs e trilhas de áudio; explicar erro quando não houver áudio ou decoder compatível.
2. Extrair/decodificar a trilha escolhida para áudio de análise em blocos. Vídeo deve chegar ao mesmo pipeline de diarização do áudio, em vez de repetir o desvio do FluidVoice.
3. Criar uma sessão de reunião com origem importada, mantendo formato original e relação temporal com o arquivo.
4. Gerar transcrição com falantes, resumos, decisões e tarefas pela mesma operação usada após a gravação.
5. Preservar o arquivo do usuário. Cancelamento limpa apenas temporários da aplicação; cópia, retenção e exclusão devem ter regras explícitas.

No macOS, avaliar decodificação nativa via AVFoundation. No Windows/Linux, a camada de decodificação precisa de implementação e validação próprias. Não foi encontrado decoder geral de áudio/vídeo nas dependências diretas examinadas; isso não exclui componentes transitivos. Não assumir FFmpeg instalado nem adicioná-lo sem avaliar distribuição, formatos e consentimento para a dependência.

## 7. Arquitetura proposta e arquivos afetados

Fluxo: gravação nativa OU importação de mídia → blocos duráveis e linha do tempo → normalização de análise → ASR + diarização → segmentos com falantes → revisão humana → resumo/decisões/tarefas → exportação.

O núcleo compartilhado deve possuir estado, persistência e coordenação. Os hosts fornecem captura/decodificação/inferência conforme capacidade real. A UI consome eventos; o fluxo de reuniões não insere automaticamente uma ata no campo de texto ativo como o ditado.

| Área | Arquivos/pontos atuais do OpenLess | Alteração proposta |
| --- | --- | --- |
| Domínio compartilhado | crates/openless-core/src/lib.rs, domains.rs, api.rs | Módulo meetings, serviço público, contratos e repositório registrados no backend |
| Interfaces nativas | crates/openless-core/src/ports.rs | Contratos próprios de captura de múltiplas trilhas, mídia e resultado temporal; preservar contrato de ditado |
| Sessões e concorrência | crates/openless-core/src/voice_session.rs | Integrar reuniões ao controle de recursos e ao bloqueio de restauração |
| Provedores/modelos | provider_resolution.rs, provider_transport.rs, llm_protocol.rs, model_store.rs, local_asr_service.rs | Reutilizar infraestrutura; acrescentar capacidades explícitas e adaptadores de reunião |
| Eventos | crates/openless-core/src/events.rs | Progresso, saúde das trilhas, estado de captura, processamento e resultados |
| Host macOS | app/src-tauri/src/recorder.rs, build.rs e lib.rs | Novo adaptador de áudio da aplicação; ponte nativa e registro de comandos |
| UI e IPC | app/src/lib/ipc/, lib/types.ts, lib/backendEvent.ts e páginas/navegação | Reuniões, gravar/importar, detalhes, player por trecho, falantes e resultados |
| Outros hosts | app/linux-egui e ios/CoreHost | Adaptação explícita do contrato e sinalização de capacidade indisponível |

Esses caminhos são relativos a openless-all, exceto crates, que fica dentro de openless-all/app. Os nomes do novo domínio são propostas, não símbolos já existentes.

BackendServices é público e construído pelos hosts; novo campo obrigatório implica atualizar inicializadores, stubs e testes. O contrato versionado BACKEND_CONTRACT_VERSION e as ferramentas de frontend precisam continuar consistentes. Evitar mudar enums existentes de forma que consumidores exaustivos deixem de compilar sem adaptação.

A persistência atual do core é baseada em JSON, com escrita atômica e integração aos gates de sincronização. Proposta inicial: diretório próprio por reunião, manifesto versionado, blocos de áudio e resultados separados, reutilizando as primitivas existentes. Não misturar esses dados no HistoryStore de ditado nem herdar silenciosamente sua retenção de gravações bem-sucedidas/falhas. Mudanças de formato exigem migração e fixtures de compatibilidade. Não há justificativa demonstrada para introduzir um banco novo neste recurso.

Sincronização de reuniões e upload de áudio não fazem parte dos requisitos apresentados; precisam de escopo específico caso desejados. Ainda assim, restauração e migração locais devem respeitar sessões ativas e não descartar dados do novo domínio.

## 8. Plataformas e dependências

- macOS: ponte Swift ou Objective-C/Rust para captura e mídia. Já há precedente de compilação Swift estática no build.rs para Gemma, mas não um runtime de reuniões. O OpenLess empacotado exige macOS 14.0; o FluidVoice exige 15.0. Preservar 14.0 com verificação de disponibilidade/fallback explícito, ou aprovar aumento do requisito. Não transportar APIs de macOS 15 sem essa decisão.
- Windows: candidato nativo é WASAPI loopback. A captura do mix de saída não é igual à captura isolada de processo; a Microsoft fornece exemplo específico para o segundo caso, com requisito de versão. Precisam ser validados seleção de fonte, coexistência com microfone e eco.
- Linux: candidato é PipeWire com stream/monitor. O host é egui, portanto implementar a tela e o adaptador desse host, não apenas a página React/Tauri.
- iOS/Android/Harmony: não prometer gravação do áudio de outras aplicações. Avaliar separadamente microfone presencial e importação, ciclo de vida e restrições de cada sistema.

Documentação primária consultada: [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos), [Microsoft WASAPI loopback](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording), [Microsoft ApplicationLoopback](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/ApplicationLoopback/README.md) e [PipeWire audio-capture](https://github.com/PipeWire/pipewire/blob/master/src/examples/audio-capture.c). São caminhos de implementação; não atestam integração já funcional no OpenLess.

Dependências adicionais ainda não aprovadas: eventual FluidAudio/modelos de diarização, ponte de captura e decoder multiplataforma. Auditar licenças e avisos dos arquivos/modelos que forem efetivamente reaproveitados; a raiz do FluidVoice declara GPLv3 e a do OpenLess AGPLv3. Não copiar o runtime privado do Fluid Intelligence.

## 9. Entregas propostas

1. Contratos, armazenamento e importação: nova sessão, manifesto versionado, jobs canceláveis, importação de áudio/vídeo e pipeline de segmentos. Validar o percurso completo com fixtures antes da captura ao vivo.
2. Falantes: integrar motor escolhido, alinhar texto/voz, conservar identidades entre blocos e fornecer edição/união manual. Cobrir mídia originada de vídeo.
3. Resumo, decisões e tarefas: serviço dedicado com provedor existente, persistência por revisão e tratamento de contexto longo. Conclui o percurso de mídia importada.
4. Gravação de reuniões no macOS: microfone + aplicação, presencial, blocos duráveis, eco, interrupções e recuperação. Conclui os quatro requisitos na plataforma inicial proposta.
5. Expansão: adaptadores e UI Windows/Linux; avaliar capacidades móveis. A entrega anterior não deve ser anunciada como paridade multiplataforma.

Não há estimativa confiável de prazo antes de uma prova de integração de captura e diarização no host Rust. Os maiores riscos técnicos são alinhamento de relógios/eco, disponibilidade de tempos no ASR, memória em reuniões longas e distribuição dos modelos.

## 10. Critérios de aceite propostos

- Gravar reunião online e presencial, reproduzir áudio e localizar trechos pela transcrição.
- Distinguir vozes de uma reunião em português; testar troca de turnos, silêncio, sobreposição e retorno do mesmo falante após mudança de bloco. Nomes reais só por indicação confirmada.
- Importar áudio e vídeo com múltiplas vozes e obter o mesmo conjunto de resultados; testar codec incompatível e vídeo sem áudio.
- Gerar resumo, decisões e ações sem inventar responsáveis/prazos; manter resultado anterior quando ocorrer falha ou cancelamento.
- Em reunião longa, memória limitada e progresso visível; sem upload de reunião inteira em memória por adaptação ingênua dos provedores batch atuais.
- Recuperar blocos finalizados após encerramento abrupto; manter lacunas visíveis após perda de dispositivo ou falha de escrita.
- Verificar fones versus alto-falantes, eco, suspensão, revogação de permissão, troca de microfone e falta de disco.
- Confirmar que falha/cancelamento de reuniões não afeta histórico de ditado, captura posterior ou restauração/sincronização existentes.
- Testes de core e contrato; testes de integração de decoder/captura; avaliação com corpus e dispositivos reais antes de declarar precisão ou latência.

## 11. Evidências e limites do levantamento

Referências locais do FluidVoice em Sources/Fluid/Services: Meeting/MeetingCaptureEngine.swift; Meeting/MeetingModels.swift; Meeting/MeetingSessionStore.swift; Meeting/MeetingAudioChunkLedger.swift; Meeting/MeetingPCMStoragePolicy.swift; Meeting/Backend/MeetingParakeetNemotronBackend.swift; Meeting/Backend/MeetingProductionParakeetNemotronRuntime.swift; Meeting/Backend/MeetingEpochAudioMaterializer.swift; Meeting/MeetingSummaryController.swift; Meeting/MeetingSummaryProvider.swift; FileTranscriptionService.swift; SpeakerDiarizationService.swift. A UI MeetingSessionCanvases integra MeetingSummaryView.

Referências locais do OpenLess em openless-all/app: crates/openless-core/src/ports.rs; types.rs; domains.rs; api.rs; events.rs; voice_session.rs; external_audio.rs; history.rs; persistence.rs; asr/elevenlabs.rs; asr/whisper.rs; polish.rs; local_asr_service.rs; src-tauri/src/recorder.rs; src-tauri/build.rs; src-tauri/tauri.conf.json. O caminho dos arquivos de core após o primeiro prefixo é sempre crates/openless-core/src/.

A consulta de grafo/impacto não encontrou VoiceSessionGate nem os caminhos ports.rs e recorder.rs. O mapa foi levantado por inspeção de código; não é um grafo determinístico completo. Antes das alterações, atualizar a indexação pertinente e repetir a análise de impacto dos símbolos concretos.

Não foram executados builds, suites de teste ou gravações. Nenhuma dependência foi instalada e nenhum arquivo dos projetos foi alterado. Este documento é um levantamento para integração; as escolhas e critérios marcados como proposta não constituem novas regras de negócio aprovadas.
