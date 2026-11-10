# feat(meetings): integrar gravação, falantes e atas no OpenLess

O OpenLess passa a oferecer reuniões com gravação de aplicação + microfone ou microfone presencial, importação de áudio/vídeo e recuperação por blocos duráveis. A tela permite transcrever com tempos e falantes, revisar/mesclar rótulos, reproduzir áudio e exportar JSON, Markdown e TXT.

A transcrição usa Parakeet v3/Nemotron locais pelo FluidAudio ou ElevenLabs. Resumos, decisões e tarefas usam um canal de IA independente, incluindo Gemini nativo, com referências à transcrição. Legendas locais aceitam português e inglês por caminhos próprios; AEC3 preserva a captura bruta. Inclui traduções portuguesas do aplicativo e dos instaladores e correções de importação AAC/vídeo, cancelamento e retomada de modelos.

## Validação

- 64 arquivos de testes TypeScript e 90 contratos JavaScript aprovados, incluindo o novo contrato dos arquivos AEC3.
- 32 testes core, 14 XCTest com modelos reais em português, 7 testes de mídia e 17 testes Gemini aprovados.
- Regressão acústica sintética AEC3 e testes de preparação/aliases da release aprovados.
- Aplicativo completo de teste e assinatura ad hoc verificados na entrega de 08/11; a revisão de 09/11 alterou somente contratos e inclusão do fornecedor no Git.

## Limites antes de publicação estável

Homologar captura/permissões/dispositivos, interface completa, download no aplicativo e chamadas reais Gemini/ElevenLabs. Não foi produzido novo DMG. Captura macOS 14+, AEC macOS 15+, modelos locais Apple Silicon; legendas exigem 8 GB. FFmpeg preexistente é opcional para codecs não atendidos pelo caminho nativo. Não há reconhecimento nominal ou união biométrica entre trilhas nem garantia de desempenho igual ao FluidVoice.

Revisão detalhada: `docs/meetings/revisao-publicacao-2026-11-09.md`. Este arquivo é apenas o texto preparado: nenhum PR foi aberto.
