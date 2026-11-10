# OpenLess 2.1.0 — notas propostas, ainda não publicado

Tag proposta: `v2.1.0-tauri`. A versão ainda não foi alterada nos manifests; não existe nova tag ou release desta entrega.

- Reuniões online com áudio da aplicação selecionada + microfone e reuniões presenciais pelo microfone.
- Importação de áudio/vídeo, blocos recuperáveis e preservação do arquivo de origem.
- Transcrição em português com identificação de falantes: Parakeet/Nemotron locais ou ElevenLabs.
- Download, verificação, cancelamento e retomada dos modelos locais.
- Legendas locais em português e outros idiomas suportados; cancelamento acústico de eco no macOS 15+.
- Resumos, decisões e tarefas com canal de IA configurável, incluindo Gemini, separado do ditado.
- Reprodução, revisão de texto/falantes, união manual e exportação TXT/Markdown/JSON.
- Traduções portuguesas do Meeting, menus, permissões e instaladores; correções de AAC/vídeo e cancelamento.

## Compatibilidade

Captura nativa: macOS 14+. AEC: macOS 15+. Modelos locais: Apple Silicon. Legendas locais: pelo menos 8 GB. Os modelos são baixados após solicitação do usuário; não vêm no instalador. Gemini e ElevenLabs exigem canais com credenciais/modelos configurados. Alguns codecs podem precisar de FFmpeg já instalado; ele não é instalado automaticamente. Falantes recebem rótulos revisáveis, sem reconhecimento de nomes ou união automática entre trilhas.

## Antes de disponibilizar

Aceitar reunião real, interface, download no aplicativo e APIs; gerar os pacotes da versão e conferir assinaturas/hashes, licença e atualizador; concluir revisão/merge autorizado. Não usar estas notas como anúncio de disponibilidade nem publicar o aplicativo de teste 2.0.2 como se fosse 2.1.0.
