# Traduções de desktop e instaladores — 07/11/2026

## Correções

- Menu do ícone na barra de menus: janela principal, saída, microfones, dispositivo padrão e estilos traduzidos para português. Identificadores `pt`, `pt-BR` e `pt_PT.UTF-8` reconhecidos.
- Inicialização do menu e da cápsula usa idioma salvo, ou idioma preferido do macOS via NSLocale antes de abrir a WebView. Português incluído na lista aceita pela cápsula. Idiomas desconhecidos usam inglês, sem cair em chinês.
- Interface: fallback inglês, traduções portuguesas de tipografia/modelos experimentais, mensagens de falha de atualização/dicionário, resultado vazio, nomes de predefinições originais e modelos de novos estilos. Não altera prompts, nomes personalizados ou entradas já salvas pelo usuário.
- Permissões: Info.plist base em inglês e InfoPlist.strings incluídos como recursos localizados para português, português do Brasil, inglês e chinês simplificado/tradicional. As mensagens de permissão do sistema seguem o idioma do macOS, independentemente da preferência na interface.
- DMG: instruções incorporadas à arte traduzidas para português com imagegen; mantidos layout, seta e alvos reais do Finder. TIFF com representações 1x/2x e DPI preservados. O alias Applications mantém seu destino funcional.
- Script de compilação/instalação do Mac: mensagens de console em português.
- Windows: idiomas NSIS/MSI incluem português do Brasil; seletor de idioma NSIS e detalhes de registro/remoção do método de entrada em português quando selecionado. Fluxo de registro permanece igual.

## Verificações

- Catálogo português: 2.475 textos, todas as chaves do catálogo inglês e nenhum texto em chinês. Isso verifica os recursos de tradução; não transforma conteúdo de usuário, termos de dicionário ou código de compatibilidade em rótulos da interface.
- `node scripts/locale-lifecycle.test.mjs`: aprovado, incluindo inicialização em pt-BR, persistência, troca de idioma e preservação de preferências de reconhecimento/tradução.
- `python3 scripts/native-localization.test.py`: quatro testes aprovados, incluindo duas verificações Rust executadas sobre os rótulos reais, recursos de permissão parseáveis/empacotados, idiomas Windows e dimensões/DPI do TIFF.
- `cargo test --offline -p openless-capsule --lib`: seis testes aprovados, incluindo correspondência entre rótulos nativos e catálogo português.
- `npm run build`: aprovado, com avisos existentes de ciclos/tamanho dos chunks.
- Contratos existentes de permissões macOS, pacote Windows e release MSI aprovados. `bash -n scripts/build-mac.sh` aprovado.
- Verificação de tipos do host Rust com artefatos locais: sem erros; não substitui compilação/linkedição/empacotamento completos.

## Entrega

### Revisão adicional do Meeting

- Corrigidas 107 ocorrências de mensagens próprias em inglês nas camadas Swift, FFI Rust, persistência e processamento de reuniões. Os códigos de erro e contratos de dados permanecem iguais.
- As 24 causas de falha do cancelamento de eco também receberam descrições em português; os avisos deixam de mostrar identificadores internos como `timestampGap` e `bridgeInitialization`.
- Nomes de idiomas no seletor do Meeting passam pelo catálogo: em português aparecem Inglês, Espanhol, Francês, Alemão e Chinês, sem o rótulo chinês literal anterior.
- Corrigidos também rótulos do catálogo geral: nomes de idiomas, comentários, marcadores, chaves de API, URL base e identificadores dos provedores. Nomes próprios de produtos e identificadores técnicos são preservados.
- Auditoria dos recursos carregados: 2.510 textos no catálogo português, sem chaves ausentes em relação ao inglês e sem caracteres chineses. Isso não constitui auditoria visual de todas as telas, textos externos ou conteúdo salvo pelo usuário.
- A transcrição final do Meeting usa Parakeet v3 multilíngue, com suporte a português, ou envia `language_code=pt` à ElevenLabs quando escolhido português. O prompt de resumo pede o idioma da transcrição. Não foi executada inferência com pesos reais nem chamada à API para confirmar precisão nesta sessão.
- O modelo EOU continua somente em inglês. Na etapa seguinte foi integrado um caminho próprio com Parakeet v3 para legendas em português, espanhol, francês e alemão, validado com áudio português e pesos reais. A transcrição final com identificação de falantes continua solicitada após a gravação.
- Mensagens originadas no macOS ou nos provedores podem seguir o idioma do sistema/serviço. Os instaladores e o aplicativo já instalados só recebem as alterações após novo build e instalação.
- Revalidados após as correções: 32 testes core, quatro testes de localização nativa, três testes de importação WAV, ciclo de idioma e build frontend. O teste de ciclo de idioma excedeu o prazo de 10 segundos na primeira execução sob carga; as duas execuções seguintes passaram. O host Rust passou na verificação com artefatos locais, com os 301 avisos já existentes; não equivale ao build completo do aplicativo.

As alterações estão na árvore de trabalho. Foi gerado `src-tauri/target/debug/bundle/macos/OpenLess.app`, com assinatura ad hoc local e recursos portugueses conferidos, após build Tauri completo. Não foi gerado/publicado novo instalador DMG/Windows; a versão já instalada e os downloads existentes continuam com seus arquivos anteriores. Não foram executados instaladores Windows ou teste visual do menu/permissões no aplicativo empacotado. Consulte [a entrega para testes](meetings/entrega-para-testes-2026-11-07.md).

Nenhuma dependência foi adicionada. Alterações anteriores de reuniões foram preservadas. Sem commit/push/PR nesta sessão devido ao bloqueio já constatado de escrita no índice Git.

### Atualização de 08/11/2026

Arte do instalador inteiramente em português, inclusive a instrução inferior. Erros de resumo do Meeting normalizados em português para evitar mensagens internas em chinês. Quatro testes de localização nativa aprovados. Testes com modelos reais em português foram executados; consulte [a entrega atual](meetings/correcoes-finais-2026-11-08.md). Não houve novo instalador DMG nem homologação visual interativa. Sem commit, push ou PR por solicitação do usuário.
