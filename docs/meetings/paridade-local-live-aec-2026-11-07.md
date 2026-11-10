# Meeting: modelos locais, legendas e cancelamento de eco

Implementação autorizada em 07/11/2026, na branch `feat/meeting-recording`. Código integrado ao OpenLess; transcrição/diarização e legendas em português executadas com os modelos reais. A homologação da captura no aplicativo e a comparação de desempenho ainda dependem do teste no Mac do usuário. Consulte a [entrega para testes](entrega-para-testes-2026-11-07.md) para o resultado mais recente.

## O que foi integrado da referência

| Recurso | Implementação no OpenLess | Limite atual |
| --- | --- | --- |
| Transcrição local com falantes | FluidAudio real, Parakeet v3 e Nemotron, análise por trilha completa, tempos por palavra | Apple Silicon; teste com áudio português e pesos reais aprovado |
| Download de modelos | Botões por modelo, progresso em bytes, cancelamento, reaproveitamento de arquivos verificados, exclusão, revisão e hashes fixos | Download real pelo URLSession falhou na resolução de hostname do ambiente do agente |
| Legendas locais durante captura | EOU 160 ms em inglês; Parakeet v3 em português/espanhol/francês/alemão com janelas de 12 s, atualização a cada 3 s, cauda provisória e controle de repetição | Apple Silicon com pelo menos 8 GB; rascunhos por fonte, sem diarização definitiva ao vivo |
| Cancelamento de eco | Mesmo WebRTC AEC3 da referência, PCM 48 kHz, alinhamento temporal e atestação de relógio antes de usar saída tratada | macOS 15+; somente aplicação + microfone; qualidade em chamada real pendente |
| Revisão de falantes | Renomear, corrigir segmentos e unir rótulos manualmente | Identidade entre trilhas não é unificada biometricamente |
| Resumo, decisões e tarefas | Canal de IA independente, incluindo transporte Gemini já integrado | Não usa Fluid Intelligence privado; chamada real à API pendente |

O microfone bruto é preservado. O core prefere a trilha tratada somente quando cobre todos os intervalos finalizados do microfone; caso contrário, processa o original. As duas versões não entram juntas na transcrição. Falhas de eco não apagam a fala gravada. Legendas têm fila e histórico em memória limitados; a captura em disco precede seu envio ao reconhecedor. Falta de capacidade das legendas produz aviso, sem descartar áudio.

Nemotron e Parakeet são carregados em sequência para reduzir o pico de memória; cada trilha tem estado independente. A diarização recebe contexto de silêncio no fim e seus resultados são limitados à duração original. Associação ambígua entre palavra e intervalos de voz permanece sem identidade, em vez de inventar um falante.

## Dependências e distribuição

- FluidAudio: `https://github.com/altic-dev/FluidAudio`, revisão `386f7195670b77f2954c7ee143ec63fcb50b6c3b`, Apache-2.0. SwiftPM configurado em `openless-all/app/src-tauri/Package.swift`, com `Package.resolved` incluído no versionamento.
- WebRTC AEC3: revisão `d9bd07ba5f614156021df666ba4052ac73cf7953`, configuração `webrtc-aec3-48k-mono-speech-protection-v2`. Binário universal e código da ponte da referência preservados em `vendor/webrtc-aec3`, com avisos upstream.
- O arquivo AEC3 da referência exige macOS 15. A ligação ocorre numa biblioteca dinâmica separada, carregada nessa versão ou superior; não foi ligado ao arquivo estático principal de destino macOS 14.
- O build Rust compila o runtime Swift, prepara os bundles de recursos do Hub/Crypto e a biblioteca AEC. O empacotamento macOS inclui esses recursos e avisos de licença. Os pesos não integram o instalador: são baixados explicitamente pelo usuário.
- Licenças do SDK, dependências transitivas e do código adaptado do FluidVoice estão em `src-tauri/vendor/licenses`; o AEC inclui seus próprios avisos. Os cartões e licenças publicados acompanham os arquivos dos modelos quando disponíveis.

| Modelo | Repositório Hugging Face | Revisão | Licença publicada |
| --- | --- | --- | --- |
| Parakeet v3 | FluidInference/parakeet-tdt-0.6b-v3-coreml | `7dd20fe6b1797d35f5e3307e8b1732d9a178edfe` | CC-BY-4.0 |
| Nemotron | altic-dev/nemotron-3-diarization-coreml | `8976c3c40a752cd6468a08f2aa08626770bc048f` | OpenMDW-1.1 |
| Parakeet EOU | FluidInference/parakeet-realtime-eou-120m-coreml | `40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355` | NVIDIA Open Model License |

## Verificação realizada

- 32 testes core passaram: documentos (13), processamento (9), seleção de trilhas/compatibilidade do manifesto (4), regressão de contratos (6).
- Nove XCTest passaram contra o SDK verdadeiro: os quatro anteriores, três testes de admissão/limites das legendas e dois testes com áudio e modelos reais (transcrição com falantes e legendas em português).
- Quatro testes WAV passaram pelo decoder Swift real: os três anteriores e regressão de áudio de 8 kHz sem lacunas artificiais na reamostragem. A amostra pública revelou esse defeito, que foi corrigido usando a continuidade da entrada e os frames efetivamente convertidos.
- Regressão acústica upstream passou através da biblioteca dinâmica do OpenLess: contrato, reset, eco sintético e fala simultânea, incluindo voz próxima fraca. Redução de eco sintético de aproximadamente 64 dB; ganho da voz próxima de −4,27/−6,46 dB nos dois cenários. Esses números descrevem a fixture, não chamadas reais nem equivalência de desempenho do aplicativo.
- `tsc` e build frontend passaram. `cargo check` e `cargo build` completos do host também passaram, com ligação do runtime Swift real. O empacotamento e a conferência dos recursos estão registrados na entrega para testes.
- Um executável mínimo Rust ligou o arquivo estático Swift real e consultou a FFI de produção: retornou os três modelos e capacidades em JSON. O arquivo estático principal não contém referências diretas à ABI AEC3.

A validação Swift usou fontes reais das revisões fixadas, com dependências direcionadas a arquivos locais temporários, pois a resolução Git não funcionou no ambiente. O sandbox interno do SwiftPM precisou ser desabilitado apenas nesse teste; o build de produção não altera essa configuração. Não foram usados reconhecedores simulados.

Logs desta sessão ficam em `/private/tmp/openless-local-meetings-core-tests.log`, `openless-native-runtime-tests.log`, `openless-native-media-final.log`, `openless-aec-final.log`, `openless-native-rust-link.log`, `openless-local-meetings-host-check.log` e `openless-local-meetings-ui-build.log`; são temporários e não fazem parte do repositório.

Para repetir a regressão acústica em macOS 15+: `python3 scripts/test-meeting-aec.py`, dentro de `openless-all/app`. Para a importação: `python3 scripts/test-meeting-media.py`. Após o build nativo preparar os recursos, os testes Swift podem ser executados com `xcrun swift test --package-path src-tauri`.

## O que falta para declarar operacional

1. Concluir a conferência do aplicativo empacotado para teste; o build nativo completo já passou. O ambiente exigiu fontes Swift locais reais, scratch temporário permitido e desativação apenas do sandbox interno do SwiftPM.
2. Validar download pelo próprio aplicativo e uma reunião com vozes conhecidas; os pesos e a inferência em português já foram executados com amostra pública. Medir tempo/memória e qualidade contra o FluidVoice usando o mesmo áudio e equipamento.
3. Validar captura real e permissões macOS, legendas em inglês, AEC com alto-falantes, troca de dispositivos, interrupção/recuperação e importação de vídeo real.
4. Conferir interface, persistência após reabrir, API ElevenLabs/Gemini, exportações e instalador empacotado.

Roteiro do usuário: [como testar](como-testar.md). Esta entrega aproxima as funções e reutiliza os componentes da referência; não comprova equivalência completa ou desempenho idêntico entre os aplicativos.
