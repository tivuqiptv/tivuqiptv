const https = require('https');
const { execSync } = require('child_process');

const deviceCode = '46118c083ed698e8fcb3325e2153f985bb4464f4';
const clientId = '178c6fc778ccc68e1d6a';
const interval = 5000;

function poll() {
  const data = `client_id=${clientId}&device_code=${deviceCode}&grant_type=urn:ietf:params:oauth:grant-type:device_code`;
  
  const options = {
    hostname: 'github.com',
    path: '/login/oauth/access_token',
    method: 'POST',
    headers: {
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
      'Content-Length': data.length
    }
  };

  const req = https.request(options, (res) => {
    let body = '';
    res.on('data', (d) => body += d);
    res.on('end', () => {
      let resp;
      try { resp = JSON.parse(body); } catch(e) { resp = {}; }
      if (resp.access_token) {
        console.log('Token received! Pushing admin filters and sort...');
        try {
          execSync('git add -A');
          execSync('git commit -m "Add 5 filterable metric cards and earliest trial expiration sorting in admin panel"');
          execSync(`git remote set-url origin https://oauth2:${resp.access_token}@github.com/tivuqiptv/tivuqiptv.git`);
          execSync('git push origin main', { stdio: 'inherit' });
          console.log('Push successful!');
          execSync('git remote set-url origin https://github.com/tivuqiptv/tivuqiptv.git');
          execSync('rm -f push_admin_filters.cjs');
        } catch (e) {
          console.error('Push error:', e.message);
        }
        process.exit(0);
      } else if (resp.error === 'authorization_pending') {
        setTimeout(poll, interval);
      } else {
        console.error('Error:', resp.error);
        process.exit(1);
      }
    });
  });

  req.write(data);
  req.end();
}

poll();
