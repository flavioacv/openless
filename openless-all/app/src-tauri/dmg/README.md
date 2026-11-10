# Instalador macOS em português

O fundo mantém a fotografia costeira, o título OpenLess, a seta e os espaços para os ícones reais do Finder. As instruções incorporadas à imagem estão em português. O alias `Applications` aponta para `/Applications` e mantém seu nome funcional.

- `installer-background@2x.png`: imagem de 1536 × 1024.
- `installer-background.tiff`: representações de 768 × 512 a 72 dpi e 1536 × 1024 a 144 dpi.
- `layout.json`: tamanho dos ícones e texto. Posições e janela em `../tauri.macos.conf.json`.

Empacote a partir de `app` com `INSTALL=0 ./scripts/build-mac.sh`. Em Apple Silicon, `scripts/macos-dmg-layout.py` grava o layout antes da compressão/assinatura do Tauri e verifica a imagem final. A arte não faz parte da interface em execução.

A imagem original foi gerada em 26/09/2026 e a tradução visual foi aplicada com imagegen em 08/11/2026, preservando a composição e os alvos de instalação.

Textos atuais: “Arraste o OpenLess para instalar” e “Arraste o OpenLess para a pasta de aplicativos”. O ambiente restrito não permite criar/montar o DMG; o aplicativo de teste foi gerado separadamente.
