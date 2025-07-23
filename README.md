# YouTube Library 🎬

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

## 🛠️ Installation

### 1. Cloner le dépôt
```bash
git clone https://https://github.com/Reaper-Official/youtu-selfhost/released/released.git
cd youtu-selfhost
```

### 2. Configuration du Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate  # Sur Windows: venv\Scripts\activate
pip install -r requirements.txt

# Copier et configurer le fichier .env
cp .env.example .env
# Éditer .env avec votre chemin de vidéos
```

### 3. Configuration du Frontend

```bash
cd ../frontend
npm install
```

### 4. Lancer l'application

**Backend :**
```bash
cd backend
uvicorn app.main:app --reload
```

**Frontend :**
```bash
cd frontend
npm start
```

L'application sera accessible sur http://localhost:3000

## 🐳 Docker

Vous pouvez aussi utiliser Docker Compose :

```bash
# Configurer MEDIA_PATH dans votre environnement
export MEDIA_PATH=/chemin/vers/vos/videos

# Lancer avec Docker Compose
docker-compose up
```

## 📝 Utilisation

1. **Configurer le chemin des vidéos** : Éditez `MEDIA_PATH` dans le fichier `.env`

2. **Scanner vos vidéos** : Cliquez sur "Scan Library" pour détecter automatiquement vos vidéos

3. **Format des noms de fichiers** : Les vidéos doivent contenir l'ID YouTube dans leur nom :
   - `Ma super vidéo - dQw4w9WgXcQ.mp4`
   - `[dQw4w9WgXcQ] Ma super vidéo.mkv`
   - `Ma super vidéo (dQw4w9WgXcQ).webm`

4. **Visionner** : Cliquez sur une vidéo pour la regarder dans le lecteur intégré

## 🔧 Configuration avancée

### API YouTube (Optionnel)

Pour de meilleures performances, vous pouvez utiliser l'API YouTube officielle :

1. Obtenez une clé API sur [Google Cloud Console](https://console.cloud.google.com/)
2. Ajoutez-la dans votre `.env` : `YOUTUBE_API_KEY=votre_cle_api`

### Structure de la base de données

La base de données SQLite stocke :
- Métadonnées des vidéos
- Statistiques de visionnage
- Chemins des fichiers
- Tags et catégories

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
