# YouTube Library 🎬 (ne fonctionne pas encore)

Un système de médiathèque personnel pour organiser et visionner vos vidéos YouTube téléchargées, inspiré de Jellyfin.

## 🚀 Fonctionnalités

- 📂 **Scanner automatique** : Détecte et importe vos vidéos YouTube depuis vos dossiers
- 🔍 **Métadonnées complètes** : Récupère automatiquement les infos depuis YouTube (titre, miniature, chaîne, etc.)
- 🎥 **Lecteur intégré** : Visionnez vos vidéos directement dans l'interface
- 🔎 **Recherche avancée** : Filtrez par titre, chaîne, statut de visionnage
- 📊 **Statistiques** : Suivez vos vidéos regardées et vos habitudes de visionnage
- 🎨 **Interface moderne** : Design inspiré de YouTube avec mode sombre

## 📋 Prérequis

- Python 3.8+
- Node.js 14+
- yt-dlp installé (`pip install yt-dlp`)

#!/bin/bash

# Script de déploiement rapide YouTube Library
# Usage: curl -sSL [URL] | sudo bash

echo "🚀 Déploiement rapide YouTube Library..."

# Télécharger et exécuter le script d'installation complet
wget -qO /tmp/youtube-install.sh https://raw.githubusercontent.com/votre-repo/install.sh
chmod +x /tmp/youtube-install.sh
/tmp/youtube-install.sh

echo "✅ Déploiement terminé!"

### 2. Ce que fait ce script

```text
🧬 Clone le dépôt GitHub youtu-selfhost

🧰 Installe les dépendances système et Python du backend

⚙️ Installe les dépendances Node.js du frontend

🗂️ Crée automatiquement les fichiers .env nécessaires

🧾 Affiche les étapes post-installation à suivre
```


## 🤝 Contribution

Les contributions sont les bienvenues ! N'hésitez pas à :
- 🐛 Signaler des bugs
- 💡 Proposer des nouvelles fonctionnalités
- 🔧 Soumettre des pull requests

## 📄 Licence

Ce projet est sous licence MIT. Voir le fichier [LICENSE](LICENSE) pour plus de détails.

## 🙏 Remerciements

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) pour l'extraction des métadonnées
- [Jellyfin](https://jellyfin.org/) pour l'inspiration du design
- La communauté open source

---

**Note** : Ce projet est destiné à un usage personnel uniquement. Respectez les droits d'auteur et les conditions d'utilisation de YouTube.
