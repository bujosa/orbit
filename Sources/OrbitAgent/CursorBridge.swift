import Foundation
import OrbitCore

enum CursorBridge {
  // The official SDK owns the sign-in; this adapter keeps its credential on the device.
  // No secret is sent back in the snapshot or verification response.
  static let source = #"""
    const fs = require('fs'), os = require('os'), path = require('path'), crypto = require('crypto');
    const input = JSON.parse(fs.readFileSync(0, 'utf8'));
    const hash = crypto.createHash('sha256').update('6:cursorcursor').digest('hex');
    const credentialPath = path.join(os.homedir(), '.t3/userdata/secrets', `provider-auth-${hash}.bin`);
    const mask = email => email?.includes('@') ? `${email[0]}•••@${email.split('@')[1]}` : undefined;
    const status = value => process.stdout.write(JSON.stringify(value));
    (async () => {
      const {Cursor, Agent} = require(input.sdk);
      if(input.action === 'login') {
        const store = {
          load: async () => undefined,
          save: async value => {
            const parent = path.dirname(credentialPath);
            fs.mkdirSync(parent, {recursive:true,mode:0o700});
            if(fs.existsSync(credentialPath) && fs.lstatSync(credentialPath).isSymbolicLink()) throw new Error('Unsafe credential path');
            const temporary = credentialPath + '.orbit-' + crypto.randomUUID();
            fs.writeFileSync(temporary, JSON.stringify(value), {mode:0o600,flag:'wx'});
            fs.renameSync(temporary, credentialPath);
          },
          clear: async () => {}
        };
        await Cursor.auth.login({openBrowser:false,store,apiKeyName:'Orbit — T3 Code',
          signal:AbortSignal.timeout(300000),onLoginUrl:url => console.log(`Open this official Cursor sign-in page:\n${url}\n`)});
        console.log('Cursor sign-in saved on this Mac. Refresh Orbit and T3.'); return;
      }
      let credential;
      try { credential = JSON.parse(fs.readFileSync(credentialPath, 'utf8')); }
      catch { status({auth:'loginRequired',note:'Sign in to Cursor on this Mac.'}); return; }
      if(credential.apiKeyExpiresAtMs && credential.apiKeyExpiresAtMs <= Date.now()) {
        status({auth:'expired',expiresAt:credential.apiKeyExpiresAtMs,note:'The Cursor credential has expired.'}); return;
      }
      const me = await Cursor.me({apiKey:credential.apiKey});
      if(input.action === 'verify') {
        const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'orbit-check-'));
        try {
          const result = await Agent.prompt('Reply exactly ORBIT_OK. Do not use tools or modify files.', {
            apiKey:credential.apiKey,model:{id:'auto'},tools:[],mcpServers:{},local:{cwd,settingSources:[]}
          });
          status({ready:result.status === 'finished' && result.result?.trim() === 'ORBIT_OK',
            limited:result.error?.code === 'rate_limit_exceeded'});
        } finally { fs.rmSync(cwd,{recursive:true,force:true}); }
      } else {
        status({auth:'authenticated',account:mask(me.userEmail),expiresAt:credential.apiKeyExpiresAtMs,
          note:'Cursor accepted this credential. Model access has not been tested.'});
      }
    })().catch(error => {
      if(input.action === 'login') { console.error('Cursor sign-in did not complete. Try again.'); process.exitCode=1; return; }
      status({auth:error.status === 401 || error.status === 403 ? 'loginRequired':'unavailable',
        note:error.status === 401 || error.status === 403 ? 'Cursor rejected this session. Sign in again.':'Cursor could not be reached.'});
    });
    """#

  static func run(action: String) async -> [String: Any] {
    guard let sdk = Paths.cursorSDK, let node = Paths.node else {
      return ["auth": "notInstalled", "note": "Install T3 Code with the Cursor SDK on this Mac."]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: ["sdk": sdk, "action": action]),
      let result = try? await ProcessRunner.run(
        node, ["-e", source], timeout: action == "verify" ? 105 : 15,
        environment: Paths.cleanEnvironment, stdin: data),
      let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any]
    else {
      return ["auth": "unavailable", "note": "Cursor did not return a usable response."]
    }
    return object
  }

  static func login() throws -> Int32 {
    guard let sdk = Paths.cursorSDK, let node = Paths.node else { throw OrbitError.agentMissing }
    // The interactive process inherits the user's terminal, never the dashboard's logs.
    let data = try JSONSerialization.data(withJSONObject: ["sdk": sdk, "action": "login"])
    let process = Process()
    process.executableURL = URL(fileURLWithPath: node)
    process.arguments = ["-e", source]
    process.environment = Paths.cleanEnvironment
    let input = Pipe()
    process.standardInput = input
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    try input.fileHandleForWriting.write(contentsOf: data)
    try input.fileHandleForWriting.close()
    process.waitUntilExit()
    return process.terminationStatus
  }
}
