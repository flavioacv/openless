# Validação da integração de reuniões — 07/11/2026

> Registro histórico. As correções e evidências mais recentes estão na [entrega de 08/11](correcoes-finais-2026-11-08.md).

## Verificações executadas

- Core: 32 testes aprovados no conjunto `meeting_documents` (13), `meeting_processing` (9), `meeting_capture_tracks` (4) e `contract_2` (6), usando `cargo test --offline -p openless-core --test meeting_processing --test meeting_documents --test meeting_capture_tracks --test contract_2`.
- Ponte nativa: quatro testes WAV via FFI real, incluindo normalização estéreo 44,1 kHz → mono 16 kHz, preservação de duração/original, blocos de 60 segundos, arquivo inválido e regressão de 8 kHz sem lacunas artificiais. Comando: `python3 scripts/test-meeting-media.py` a partir de `openless-all/app`.
- TypeScript: `tsc --noEmit` aprovado. Build frontend `npm run build` aprovado, incluindo verificações existentes de prebuild.
- Swift: compilação da biblioteca estática e verificação dos três símbolos FFI executadas.
- FluidAudio real compilado com os adaptadores locais/live; nove XCTest, sem ignorados na execução com os pesos, e regressão acústica AEC3 aprovados. Inclui transcrição final com diarização e legendas em português usando pesos e áudio reais. Ligação estática com Rust e consulta JSON pela FFI também verificadas.
- Host: `cargo check`, `cargo build` e build Tauri completos passaram. `src-tauri/target/debug/bundle/macos/OpenLess.app` gerado com recursos Swift, cápsula, AEC, licenças e permissões traduzidas conferidos; assinatura ad hoc local verificada com `codesign --verify --deep --strict`. Usadas dependências Swift reais locais e scratch temporário permitido no ambiente restrito.

## Limites do resultado

O aplicativo empacotado foi gerado, mas não foi executada uma reunião real com permissões/dispositivos do usuário nem chamada ElevenLabs/LLM. Um MOV real com áudio e vídeo foi produzido com ffmpeg já instalado e enviado ao decoder: AVFoundation retornou -11800 com erro subjacente -1 neste ambiente restrito. Não contar o teste de vídeo como aprovado. Ele é explícito por `OPENLESS_MEETING_TEST_VIDEO=1`; os quatro testes de áudio passam. A precisão foi conferida apenas na amostra pública usada para integração, sem avaliação representativa de reuniões ou benchmark contra FluidVoice.

Há implementação de captura, importação áudio/vídeo, diarização via ElevenLabs ou Parakeet/Nemotron locais, resumo estruturado, legendas EOU em inglês e Parakeet em português/espanhol/francês/alemão e AEC3 no macOS 15+. Os pesos foram baixados por HTTPS, conferidos contra os hashes publicados e executados em português. O download através do URLSession e as permissões/captura/API precisam de aceite no Mac do usuário. Não há identificação automática da mesma pessoa entre trilhas independentes; há união manual no editor. Detalhes atuais e execução na [entrega para testes](entrega-para-testes-2026-11-07.md).

O documento `validacao-2026-11-07.md` registra somente a primeira etapa, anterior à integração de host/interface.
