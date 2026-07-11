const body = {
  type: 'web_service',
  name: 'gallery-on-the-go-backend',
  ownerId: 'tea-d4e4jp3gk3sc73bg21ug',
  repo: 'https://github.com/Zenx-Web/gallery-on-the-go',
  autoDeploy: 'yes',
  branch: 'main',
  serviceDetails: {
    env: 'node',
    envSpecificDetails: {
      buildCommand: 'npm install && npm run build:shared && npm run build:server',
      startCommand: 'cd server && npm start'
    },
    plan: 'free'
  }
};

fetch('https://api.render.com/v1/services', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer rnd_DSc839FW5s76IYUE431WsMpKFOFq',
    'Content-Type': 'application/json'
  },
  body: JSON.stringify(body)
})
.then(r => r.json())
.then(data => {
  console.log(JSON.stringify(data, null, 2));
})
.catch(console.error);
