# Integração seletiva do oficial — 24/11/2026

Base local: `b19cf014`, main do fork, versão 2.1.0. Referências oficiais obtidas com `git fetch https://github.com/Open-Less/openless.git main beta`: Stable `962705d56984b4c267f450d016aa16b3a881e4b4`, Beta `c9d40c384c8835f6f0a81e1bf0a0d0322d7b891a`.

## Correções incorporadas

| Commit oficial | Comportamento |
| --- | --- |
| `50e367b2` | macOS aceita a autorização válida de AVCaptureDevice quando AVAudioApplication retorna estado desatualizado. Nova solicitação e reinício Beta preservam microfone já autorizado. |
| `1f057451` | ASR Whisper usa blocos de até dez minutos por padrão, procura pausas próximas ao corte e preserva todos os bytes. Mantém configuração de envio integral do provedor personalizado. macOS copia a transcrição quando perde o destino de inserção. |
| `6a7b5bb6` | Arquivos estranhos, como iscas de antivírus, não bloqueiam a primeira inicialização da sincronização criptografada. Resíduos reconhecidos continuam exigindo recuperação. |
| `aff704b1` | Comando de abertura da edição por voz é assíncrono no Windows para evitar deadlock do WebView2. A restrição à janela principal permanece. |
| `c9350455` | Exportação Android escreve os bytes ZIP reais no documento SAF `content://`, propagando erros de codificação e escrita. |
| `7b2c5eca` | Assistente Android limita a altura da superfície e mantém acessível o início de cartões altos e seus controles de navegação. |

Patches aplicados sobre os arquivos locais, sem merge da árvore oficial. Adaptada a declaração do módulo de ZIP à organização local. Fixture do assistente adaptada à estrutura local e ao idioma explícito de teste; não importa CSS desktop inexistente neste fork. Adicionado harness macOS para executar os testes do resolvedor real de permissões sem iniciar captura nem pedir autorizações. O lockfile dos testes backend estava sem `opus-pure`, já declarado no Core local; atualizado offline sem acrescentar dependência ao aplicativo.

## Preservação do fork

Mantidos português, reuniões, processamento/importação e diarização locais, Opus, preferências próprias de inserção rica, versão 2.1.0, assinatura e feeds `flavioacv/openless`. Nenhuma dependência de produção, chave, endpoint, versão ou workflow foi substituído. Os arquivos de traduções e reuniões não foram editados.

## Validação

- Build TypeScript/Vite aprovado; avisos de ciclos entre chunks e tamanho de bundle existentes permanecem.
- Verificação TypeScript após os ajustes finais aprovada.
- Nove testes de contratos: tradução/locale, propriedade do repositório, feeds e chave Android, abertura de edição por voz.
- Seis testes do módulo real de permissões macOS aprovados.
- Os 36 testes Whisper passaram, incluindo limite de upload, corte em pausa e preservação integral do áudio.
- Regressões de reuniões: 26 aprovadas (captura, documentos e processamento); teste de provedor com socket ignorado por configuração explícita da suíte.
- Dois testes de exportação ZIP aprovados, incluindo reimportação dos bytes gerados pelo Core e propagação de erros.
- Playwright: cinco testes aprovados; um ignorado por projeto, pois o teste CDP de toque é exclusivo do Chromium. Inclui Chromium e WebKit em 390x600 e 740x360.
- Core completo: 1.395 aprovados, três ignorados, dois falhos. `asr_usage_counts_local_and_cloud_dictations_and_the_latest_kind` e `asr_usage_ignores_entries_without_a_successful_recognition` usam timestamps fixos de 18/10/2026 e retenção de 30 dias, portanto os registros já expiraram em 24/11/2026. Esses testes e a implementação de contagem não foram alterados. A suíte completa não está verde.

Os navegadores de teste foram baixados após autorização do ambiente. Não houve teste nativo de microfone/ditado, instalação, atualização assinada, Android físico ou Windows. O teste de permissões compila o módulo de produção no macOS, mas valida a resolução dos estados sem interagir com TCC.

Consultas obrigatórias de impacto foram feitas ao MCP; o grafo não encontrou os símbolos. A análise complementar usou histórico, diffs e referências textuais locais.

## Diferenças ainda pendentes

Este lote não sincroniza integralmente o fork. A Stable oficial contém mudanças maiores que requerem adaptação conjunta e validação própria:

- Gemini/Thinking e modelos (`a689f204`), com sobreposição ao serviço de provedores e necessidade de tradução das mensagens novas.
- Áudio, cancelamento de eco de ditado e processamento (`ee0e3cd4`, `caa1b204`), com sobreposição às reuniões e à implementação local de áudio.
- Afinidade de thread, handles, foco e ciclo de vida da cápsula Windows/macOS; precisam avaliação como conjunto e aceitação nativa.
- Novo assistente desktop, contexto do cursor, inserção ao vivo, reorganização de configurações, uso de serviços e preferências aprendidas; alteram contratos, telas e traduções locais.
- Preferências e eventos de sincronização, teclado Android e demais alterações multiplataforma.
- Infraestrutura CDN/OSS, publicação e troca de versões oficiais: não transplantadas para os canais assinados do fork.
- Beta posterior à Stable inclui trabalho intermediário e recuperação de gravações; não tratada como atualização estável neste lote.

Nenhuma release ou merge na main faz parte desta integração.
