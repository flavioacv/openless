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

## Validação do primeiro lote

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

## Continuação: consolidação da Stable

A continuação integra o código da Stable `962705d5` do Core e desktop, resolvendo as diferenças com o fork. A PR [#4](https://github.com/flavioacv/openless/pull/4), do primeiro lote, já foi integrada externamente. Esta continuação usa a branch `feat/upstream-stable-integration-2026-11-24` para uma nova revisão. O primeiro lote acima permanece como histórico.

### Comportamento incorporado

- Gemini: URLs sem versão são normalizadas, novos padrões de modelo, Thinking, erro orientando a ativação necessária, cancelamento e políticas de cache de prompts. Preservado o transporte de resumos de reuniões e seus cabeçalhos personalizados.
- Core: estatísticas locais de consumo e tokens informados pelo provedor, sem somar campos de cache/raciocínio que possam já estar incluídos; preferências opcionais de formatação, contexto do cursor e revisão de inserção final.
- Interface: assistente desktop persistente, configuração de serviços em diálogo, início limitado por prazo, navegação e transições, subpáginas de configurações, tela de uso, melhorias de geometria, rolagem e acessibilidade.
- Ditado: inserção ao vivo com validação do editor/alvo, preservação de transcrições, limites de upload e sincronização das preferências portáveis.
- Cápsula: tema em janelas visíveis e ocultas, foco e propriedade de entrada, monitores, handles Windows e propriedade da thread de eventos. CPAL 0.15.3 e tauri-runtime-wry 2.12.2 usam as cópias corrigidas do oficial, com suas licenças e notas de patches.
- Áudio: cancelamento de eco de reprodução opcional e local, otimizações de DSP e buffers, espectro e efeitos de sistema Android, opções separadas de arquivo bruto/processado. O AEC de reuniões existente continua independente.
- Android: aprendizado, sugestões em inglês, filas Rime, pinyin aproximado e exportação/importação dos dados do teclado, além das correções do primeiro lote.
- Sincronização: eventos vinculados à origem do serviço, preferências portáveis e preservação das configurações específicas de cada dispositivo.
- Linux: correções de ditado, monitoramento de captura, processamento de áudio, referência de reprodução e diagnóstico com nível de logs; mantido Less Computer.
- iOS: atualização das fontes do host e áudio, buffers/conversão, controles de áudio e preparação isolada do Core. A sobreposição de contratos iOS é aplicada à cópia em `CoreHost/.build/core-source`, preservando o Core compartilhado e o campo próprio de baixo consumo. Scripts de preparação/build/teste e lockfile acompanham esse arranjo.
- Entrada remota: favicon e alinhamento do botão de copiar.
- CI/distribuição: diagnósticos e testes da propriedade de thread, símbolos verificáveis por revisão imutável, compilação Windows reaproveitada entre NSIS/MSI, seletor de arquitetura, reutilização de cache e verificação de todos os gates necessários do commit de reparo. O pipeline do fork continua publicando somente drafts assinados no GitHub.

### Recursos locais preservados explicitamente

Português, reuniões, processamento/importação/diarização próprios, Opus, preferências de inserção rica, versão 2.1.0, chave e feeds próprios continuam presentes. Os diretórios de implementação de reuniões e a configuração Tauri de identidade/versão não foram substituídos. Os novos controles, assistente e tela de uso têm tradução para português, com regressão de navegador específica.

O oficial retirou Less Computer e baixo consumo da interface; essa retirada **não** foi incorporada. Permanecem os controles e atalhos com adesão explícita, janelas e comandos autorizados, política de recursos, aviso de saúde da cápsula e classificação local da preferência de baixo consumo. Mantidas as predefinições de vocabulário locais e sua tradução; incorporada separadamente a correção de posição do botão de nova palavra.

O atualizador conserva GitHub Releases do fork, chave própria e os manifestos existentes. A comparação Android usa precedência SemVer: metadados `+build` não oferecem reinstalação/downgrade. Não foram copiados os endpoints CDN/OSS nem as chaves do oficial.

Manifests de dependências do frontend e Core não foram alterados. As correções de bibliotecas nativas usam as mesmas versões já existentes. Manifests/locks auxiliares de testes e iOS foram ajustados para o Core atual e para testar módulos reais sem iniciar Tauri/captura.

### Validação da continuação

- `npm test`: build TypeScript/Vite e os 166 arquivos de testes descobertos passaram.
- `cargo check --manifest-path src-tauri/Cargo.toml --locked --offline`: host macOS aprovado, com avisos Rust/upstream existentes.
- `cargo check -p openless-native-capsule --locked --offline`: cápsula nativa aprovada.
- Navegadores Chromium e WebKit: 47 testes de assistente/startup/uso/Android aprovados, um teste CDP ignorado no WebKit; 12 testes de tema/inserção ao vivo aprovados; quatro testes específicos do português aprovados, incluindo reuniões, uso e assistente.
- iOS isolado: 1.500 testes do Core preparado aprovados, três ignorados; 76 testes do host aprovados. A preparação validou que os fontes compartilhados não foram modificados.
- Reuniões: 26 testes de documentos, processamento e trilhas aprovados.
- Módulos reais sem Tauri: sete testes de permissões macOS, sete de restauração de clipboard, dois de ZIP, um de precedência SemVer do atualizador e um de preservação das preferências do fork aprovados. O hit-test Windows tem zero testes executados neste macOS, conforme seu cfg.
- Propriedade de thread: sete testes aprovados e dois casos compile-fail confirmando que o proprietário e o empréstimo não cruzam suas fronteiras.
- Conversão Swift de áudio: 32 combinações aprovadas sem abrir microfone. Localização nativa: quatro testes Python e dois testes Rust do menu aprovados.
- As datas fixas expiradas dos testes de estatísticas foram substituídas por datas recentes relativas ao relógio da execução, sem alterar a retenção do aplicativo. Foi removida uma duplicação de registro de preferência de eco surgida na consolidação.
- Core compartilhado, repetição final: **1.481 aprovados, zero falhas, três ignorados**. Uma execução anterior teve timeout em `regex_replace_batch_email_format` sob carga de compilação; o teste passou na repetição final. O limite de proteção de regex do aplicativo não foi relaxado.
- Suíte completa `src-tauri/backend-tests`: aprovada, incluindo os contratos do fork, permissões, clipboard e atualização. Módulo real do gravador: **93 aprovados**, zero falhas.

A validação de Linux no compilador macOS foi interrompida por dependências `cfg(target_os = "linux")`, e não representa uma validação Linux. Não foram adicionadas dependências Linux ao target macOS para contornar essa fronteira.

### Limites e diferenças intencionais

- Referência desta integração: Stable `962705d5`. Trabalho intermediário da Beta `c9d40c38` não foi tratado como versão estável.
- Mantidos os recursos que o fork já oferecia, mesmo quando retirados no oficial. A árvore não pretende ser idêntica ao upstream.
- Mantidos canais, versão, assinatura, fluxo de drafts e metadados de distribuição próprios. Infraestrutura CDN/OSS e remoções extensas de documentação do oficial ficaram de fora.
- Validações macOS não equivalem a aceitação nativa no Windows, Linux, Android ou iPhone. O ambiente não possui o projeto Android gerado nem SDK Android; os testes Kotlin/Android devem rodar na CI/dispositivo. O host Linux tem dependências condicionais ao Linux e não pode ser validado como Linux pelo compilador macOS.
- Não foram instalados aplicativos, concedidas permissões TCC, utilizados microfones reais, baixados modelos de IA, alterados secrets, criadas releases ou feito merge na main.

Consultas de impacto foram executadas para as fontes e contratos editados. O grafo continua sem indexar os símbolos do projeto; foram usados histórico, comparação em três vias, referências e testes para complementar a análise.
