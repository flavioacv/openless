# Correções para testes — 08/11/2026

As pendências de código encontradas na revisão foram corrigidas. A homologação de captura, interface e APIs no Mac do usuário continua necessária. Sem commit, push ou PR no OpenLess, conforme solicitado.

## Correções

- Importação de vídeo: buffers vazios de fim de trilha deixam de interromper uma importação válida. Vídeo com PCM é lido nativamente; áudio é convertido para WAV mono de 16 kHz em blocos de até 60 segundos.
- Importação AAC: leitura por ExtAudioFile com erros verificados evita a exceção Objective-C que encerrava o processo. O original permanece preservado.
- Se o decodificador nativo falhar antes de gravar blocos, o aplicativo tenta o FFmpeg já instalado em `/opt/homebrew/bin/ffmpeg`, `/usr/local/bin/ffmpeg` ou `/usr/bin/ffmpeg`. Não baixa nem instala programas e não adiciona pacotes ao projeto. A execução usa argumentos fixos e permite somente protocolos locais `file,pipe`. Sem esse programa, a compatibilidade fica limitada aos codecs nativos disponíveis e o erro explica a falha. Não ocorre envio de mídia à rede.
- Cancelamento encerra o processo auxiliar e finaliza os WAV já gravados. A finalização da captura tenta salvar todas as trilhas mesmo quando uma delas falha.
- Corrigida a retenção da memória dos buffers de áudio durante a cópia para evitar leitura de armazenamento liberado.
- Download de modelos: cancelamento de URLSession recebe mensagem em português; retomada reaproveita arquivos verificados. Substituição corrompida preserva o modelo válido anterior.
- Erros de resumo do Meeting agora passam por mensagens próprias em português, evitando expor mensagens internas em chinês e corpos brutos de respostas dos provedores.
- Arte do instalador macOS: “Arraste o OpenLess para instalar” e “Arraste o OpenLess para a pasta de aplicativos”. TIFF com as duas resoluções preservadas.

## Evidências

| Verificação | Resultado |
| --- | --- |
| Documentos, processamento, seleção de trilhas e regressão do core | 32 testes aprovados |
| Ponte Swift, modelos reais, buffers, download e cancelamento | 14 testes aprovados |
| Importação de mídia | 7 testes aprovados: WAV, estéreo, 8 kHz, blocos longos, arquivo inválido, MOV com AAC/PCM e AAC isolado |
| Transporte Gemini | 17 testes aprovados, sem chamadas pagas |
| Localização nativa e arte do instalador | 4 testes aprovados |
| Cancelamento acústico AEC3 | Regressão sintética aprovada; não mede desempenho em uma chamada real |
| Interface | Build TypeScript/Vite e ciclo de idioma aprovados; homologação visual ainda necessária |

Os testes de download exercitam o instalador e URLSession reais com respostas HTTP controladas em memória; não comprovam a conexão pública dentro do aplicativo. Inferência local e legendas em português usam pesos reais e amostra pública portuguesa. O teste de cancelamento usa um processo auxiliar controlado; os testes MOV/AAC usam o decodificador real. Na máquina de validação havia FFmpeg disponível.

## Abrir e testar

Saia completamente da cópia antiga pelo ícone da barra do Mac. Abra:

```sh
open "/Volumes/Externo 1/projetos/zurc/openless/openless-all/app/src-tauri/target/debug/bundle/macos/OpenLess.app"
```

A cópia empacotada dispensa Vite. É um aplicativo de teste com assinatura ad hoc, sem notarização. Para executar em desenvolvimento, use `npm run tauri -- dev` em `openless-all/app`. Siga [Como testar](como-testar.md) para configurar Parakeet/Nemotron ou ElevenLabs e o canal Gemini independente.

Primeiro importe um áudio ou vídeo curto com duas vozes em português. Transcreva, confira os rótulos, gere resumo/decisões/tarefas e exporte. Depois grave uma aplicação + microfone ou uma conversa presencial, confira as permissões e repita o fluxo. Não depende do Google Meet; captura o áudio da aplicação selecionada.

## Limites restantes

- Este ambiente bloqueia serviços do macOS necessários para criar/montar DMG (`hdiutil`: Device not configured; DiskManagement/DiskArbitration indisponíveis). A arte e o pipeline foram corrigidos, mas nenhum novo DMG foi produzido. Fora deste ambiente, o comando do projeto é `INSTALL=0 ./scripts/build-mac.sh`, em `openless-all/app`.
- Captura interativa, permissões, dispositivos, menus, reprodução e interface completa precisam de aceite no Mac. O navegador de automação também foi bloqueado pelos serviços do ambiente; não foi removido seu sandbox.
- Não foram usadas credenciais nem executadas chamadas pagas de Gemini/ElevenLabs. Validar os canais e modelos selecionados no aplicativo.
- Diarização não reconhece nomes reais nem une automaticamente a mesma pessoa entre trilhas distintas; há edição e união manual. Não foi demonstrada igualdade de desempenho com FluidVoice.
- Captura nativa é macOS 14+; AEC exige macOS 15+. Política de retenção automática não foi definida: originais continuam preservados.
