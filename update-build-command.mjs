const body = {
  serviceDetails: {
    envSpecificDetails: {
      buildCommand: 'npm install --include=dev && npm run build:shared && npm run build:server',
      startCommand: 'npm run start --workspace=server'
    }
  }
};

fetch('https://api.render.com/v1/services/srv-d998nlgk1i2s73drd6ug', {
  method: 'PATCH',
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
