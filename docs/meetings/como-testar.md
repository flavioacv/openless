# Como testar reuniões no OpenLess

Este roteiro se refere ao código em desenvolvimento. Ainda falta o aceite de uma reunião real no aplicativo; a versão instalada anteriormente não recebeu estas alterações.

Para transcrição final em português, mantenha **Idioma falado → Português (Brasil)** e escolha Parakeet + Nemotron locais ou ElevenLabs. Os resumos são solicitados no idioma da transcrição. As legendas em português usam Parakeet v3, com atualização por trechos curtos; o modelo EOU é usado somente no caminho de inglês. Em Configurações, escolha **Idioma da interface → Português** para os rótulos do aplicativo; as permissões nativas seguem o idioma do macOS.

## Preparação

No Mac, abra o aplicativo a partir do projeto:

```sh
cd "/Volumes/Externo 1/projetos/zurc/openless/openless-all/app"
npm run tauri -- dev
```

O comando também compila a parte nativa em modo de desenvolvimento. O frontend isolado (`npm run dev` no navegador) não permite testar gravação, importação ou chamadas nativas. Se o Cargo parar em dependências ausentes ou em um bloqueio de outra compilação, o aplicativo ainda não estará executando esta implementação.

Para gerar o instalador DMG localmente em modo release:

```sh
cd "/Volumes/Externo 1/projetos/zurc/openless/openless-all/app"
npm run build:dmg
```

O comando gera o instalador sem instalar automaticamente. No Apple Silicon, a versão 2.1.0 fica em `src-tauri/target/release/bundle/dmg/OpenLess_2.1.0_aarch64.dmg`; no Intel, o sufixo é `_x64.dmg`. Abra o DMG e instale para testar. Requer as ferramentas nativas de build e as dependências npm instaladas (`npm ci` na primeira preparação). Sem certificado Apple configurado, usa assinatura ad hoc local. O primeiro build precisa de internet para resolver dependências. Antes de abrir a nova cópia, saia completamente da versão antiga pelo ícone da barra do Mac.

Em Configurações → Modelos e provedores de IA:

1. Para transcrição com falantes via API, tenha um canal ElevenLabs ativo, com chave e modelo configurados. Para uso local, siga a seção abaixo; essa etapa não precisa de chave.
2. Para resumos e tarefas, use seu canal Gemini ativo com a chave/modelo que já utiliza, ou outro canal de IA por API compatível.
3. O Meeting tem seletores independentes para essas duas etapas. Escolher um canal aqui não altera o canal de ditado. Cada opção usa o modelo configurado naquele canal; altere o modelo nas configurações do canal.
4. Opções "canal atual" seguem a configuração geral no momento de iniciar a operação. Se o canal atual de fala não for ElevenLabs, selecione explicitamente um canal ElevenLabs no Meeting.

O primeiro build nativo resolve FluidAudio e suas dependências via SwiftPM e precisa de internet e Xcode com compilador Swift compatível (a validação desta sessão usou Swift 6.4). Os pesos dos modelos são baixados separadamente pelo aplicativo. Não selecione um ASR qualquer esperando que forneça falantes e tempos: o adaptador precisa suportar esses resultados.

## Modelos locais e legendas

1. Em **Reuniões**, localize os modelos locais e baixe **Parakeet** e **Nemotron**. Aguarde ambos indicarem instalação concluída. Reserve espaço para os pesos e para os arquivos temporários de download; cada modelo mostra progresso em bytes e sua licença.
2. Em **Transcrição e falantes**, escolha a opção local Parakeet + Nemotron. Use-a no primeiro teste abaixo para processar o arquivo sem enviar áudio à ElevenLabs. O resumo continua usando o canal de IA selecionado, por exemplo Gemini.
3. Os modelos locais exigem Apple Silicon. Nemotron e Parakeet são carregados em sequência após solicitar a transcrição final. Download incompleto ou danificado impede o processamento e mantém o áudio.
4. Para legendas em português durante a gravação, baixe **Parakeet**, mantenha **Português (Brasil)** e habilite **Legendas locais ao vivo** antes de gravar. Exige Apple Silicon com pelo menos 8 GB. Aguarde alguns segundos de áudio para a primeira atualização. Para legendas em inglês, baixe também **Parakeet EOU** e escolha inglês.
5. As legendas são rascunhos separados por fonte, sem identidade final de falantes. Finalize e clique em transcrever para obter tempos/falantes e depois gerar o resumo. Sob carga, as legendas podem atrasar ou perder atualizações; isso não descarta a gravação.
6. É possível cancelar o download e tentar novamente; arquivos completos e verificados são reaproveitados. Excluir um modelo remove somente seus pesos instalados, sem apagar reuniões.

## Primeiro teste: um arquivo com duas vozes

1. Abra **Reuniões** e escolha **Importar áudio ou vídeo**. Para começar, use um WAV curto, com cerca de um minuto e duas vozes distintas.
2. Aguarde a importação e confira os blocos de áudio na reunião criada. O original não é alterado.
3. Em **Transcrição e falantes**, selecione Parakeet + Nemotron locais ou seu canal ElevenLabs. Clique em **Transcrever e identificar falantes**. Na opção ElevenLabs, esse comando envia o áudio ao provedor; na opção local, processa no Mac.
4. Confira a transcrição, os tempos e o retorno de um mesmo falante depois de outra pessoa falar. Ouça os trechos para comparar com a fonte.
5. Renomeie os rótulos de falantes se desejar. São identidades de voz, não nomes reais reconhecidos automaticamente. Quando dois rótulos forem a mesma pessoa, selecione a união manual no editor. Corrija as atribuições/textos e **Salve as alterações**.
6. Em **Resumo e tarefas**, selecione o canal Gemini que já utiliza. Clique em **Gerar resumo e tarefas**. Essa etapa envia a transcrição ao LLM, não precisa reenviar o áudio.
7. Verifique se decisões e tarefas correspondem à conversa e se responsáveis/prazos não informados continuam sem definição. Exporte TXT, Markdown ou JSON.

WAV, MOV com áudio PCM/AAC e AAC isolado passaram em testes automatizados reais. Se a decodificação nativa falhar antes de salvar blocos, o aplicativo pode usar FFmpeg já instalado em `/opt/homebrew/bin`, `/usr/local/bin` ou `/usr/bin`; ele não é baixado nem incluído no pacote. Sem FFmpeg, o suporte depende dos codecs nativos do macOS. Teste seus formatos no aplicativo. Chamadas reais de IA ainda exigem aceite.

Antes de abrir a nova cópia do OpenLess, **saia completamente da versão antiga pelo menu do ícone na barra do Mac**. Abrir duas cópias pode ativar a janela do processo antigo, sem carregar o código novo. O aplicativo empacotado não precisa do servidor Vite; consulte o caminho na [entrega atual para testes](correcoes-finais-2026-11-08.md).

## Segundo teste: áudio de uma aplicação + seu microfone

1. Use fones de ouvido e confira o microfone padrão nas configurações de som do macOS.
2. Abra uma chamada ou reproduza uma conversa em uma aplicação. Pode ser navegador com Meet, Zoom, Teams, um vídeo ou outro programa que o macOS permita capturar. Não há integração obrigatória com Google Meet.
3. Em **Reuniões**, informe título/idioma e clique em **Buscar aplicações**. Permita o acesso à gravação de tela/áudio do sistema quando solicitado; permita também o microfone. Se o macOS exigir, reinicie o aplicativo e repita a seleção.
4. Em **Fonte da gravação**, selecione a aplicação que está emitindo o áudio. Selecionar o navegador pode incluir o áudio de outras abas desse mesmo navegador. Este modo não é um gravador global de todo o áudio do computador.
5. No macOS 15+, a opção de cancelamento de eco fica disponível para aplicação + microfone. Para conferi-la, faça também uma gravação curta usando os alto-falantes: observe o estado de aquecimento/ativo ou avisos. O aplicativo preserva a trilha original e só prefere a trilha tratada na transcrição quando ela cobre toda a captura. Clique em **Iniciar gravação**, grave de um a dois minutos e clique em **Finalizar gravação**.
6. Ouça os blocos para confirmar que as duas fontes foram captadas. Em seguida execute transcrição, revisão e resumo como no primeiro teste.

Para uma conversa presencial, selecione **Presencial · microfone**. Nesse modo, a captura vem somente do microfone.

A gravação fica independente do sucesso da transcrição/resumo. Legendas ao vivo são opcionais; transcrição final e resumo são solicitados pelos botões. A identidade é mantida dentro de cada trilha processada; a mesma pessoa em duas trilhas distintas não é automaticamente unificada. No macOS 14 não há AEC; use fones para reduzir vazamento entre aplicação e microfone.

Se aparecer conflito com ativação por voz, desative a ativação por voz nas configurações antes de iniciar a reunião. Se uma operação for interrompida, use **Recuperar áudio salvo** antes de reprocessar.

## Critério de aceite

O fluxo só deve ser considerado operacional após confirmar, no mesmo aplicativo: captura das fontes esperadas, reprodução, transcrição com falantes e tempos coerentes, edição persistente após reabrir, resumo pelo canal selecionado e exportação. Teste primeiro com conteúdo curto e conhecido; mantenha o áudio para conferir os resultados.
