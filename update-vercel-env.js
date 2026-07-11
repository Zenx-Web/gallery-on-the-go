import { spawn } from 'child_process';

function addEnv(key, value) {
  return new Promise((resolve, reject) => {
    console.log(`Adding ${key}=${value} to Vercel...`);
    
    // Remove env variable first to avoid duplicates or errors
    const rm = spawn('npx', ['vercel', 'env', 'rm', key, 'production', '--yes', '--scope', 'zenxs-projects-fb90d3c5'], { shell: true });
    rm.on('close', () => {
      // Add the env variable
      const add = spawn('npx', ['vercel', 'env', 'add', key, 'production', '--yes', '--scope', 'zenxs-projects-fb90d3c5'], { shell: true });
      
      add.stdin.write(value);
      add.stdin.end();

      let output = '';
      add.stdout.on('data', d => output += d);
      add.stderr.on('data', d => output += d);

      add.on('close', (code) => {
        if (code === 0) {
          console.log(`Successfully added ${key}`);
          resolve();
        } else {
          console.error(`Failed to add ${key}:`, output);
          reject(new Error(output));
        }
      });
    });
  });
}

async function run() {
  try {
    await addEnv('NEXT_PUBLIC_API_URL', 'https://gallery-on-the-go-backend.onrender.com');
    await addEnv('NEXT_PUBLIC_WS_URL', 'wss://gallery-on-the-go-backend.onrender.com');
    console.log('All env vars updated! Redeploying to Vercel...');
  } catch (e) {
    console.error(e);
  }
}

run();
