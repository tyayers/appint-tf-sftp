// index.js
// ------------------------------------------------------------------
//
// Copyright 2022 Google LLC.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

const functions = require('@google-cloud/functions-framework');
const AdmZip   = require('adm-zip');
const Client = require('ssh2-sftp-client');
const {Storage} = require('@google-cloud/storage');
const textSuffixes = ['.js', '.json', '.txt', '.md', '.yaml', '.xml', '.xsl', '.wsdl', '.html'];
const fs = require('node:fs');

const storage = new Storage();
const bucket = storage.bucket(process.env.BUCKET_NAME);

const base64Decode = (b64EncodedBuf) => Buffer.from(b64EncodedBuf.toString('utf8'), 'base64');
const isTextFile = n => textSuffixes.find(s => n.endsWith(s));
const jsonFormat = entry => {
        let name = entry.entryName,
            encoding = (isTextFile(name)) ? 'utf8' : 'base64',
            b = entry.getData(),
            r = {
              name,
              stamp: entry.header.time,
              contents: b.toString(encoding)
            };
        return r;
      };
const invalidRequest = res => res.status(400).type('text/plain').send('invalid request');
const sftpClient = new Client();
console.log("creating sftp client");
try {

  console.log("FTP host: " + process.env.SFTP_HOST);
  sftpClient.connect({
    host: process.env.SFTP_HOST,
    port: process.env.SFTP_PORT,
    username: process.env.SFTP_USER,
    password: process.env.SFTP_PW
  });

} catch(err) {
  console.error(err);
}

functions.http('sftp-zip-handler', async (req, res) => {
  if ('POST' != req.method) {
    invalidRequest(res);
    return;
  }

  let result = [];
  let fileLocation = req.query["fileLocation"];
  if (fileLocation) {

    let filePieces = fileLocation.split("/");
    let fileName = filePieces[filePieces.length - 1];
    let dirName = "./" + fileName.replace(".zip", "");

    try {
      console.log("Downloading " + fileLocation);

      await sftpClient.get(fileLocation, "./" +  fileName);
    } catch (err) {
      console.error('Downloading failed:', err);
    }

    const data = fs.readFileSync("./" +  fileName);
    if (!fs.existsSync(dirName))
      fs.mkdirSync(dirName);

    console.log("Unzipping " + fileName);
    new AdmZip(data).extractAllTo(dirName, true);
    
    let files = fs.readdirSync(dirName);
    for (let file of files) {
      
      console.log("Uploading file " + file + "to cloud storage.");
      let storageUploadResult = await bucket.upload(dirName + "/" + file, {
        destination: fileName.replace(".zip", "") + "/" + file
      });

      result.push(fileName.replace(".zip", "") + "/" + file);
    }

    console.log("Cleaning up files");
    fs.rmSync(dirName, { recursive: true, force: true });
    fs.rmSync("./" + fileName);
  }

  res.send({result});
});
