const fs = require('fs');
const version = '2';
const maxValue = 10;
const fileName = './liveness.txt';
let content = '';
let writeFile = true;
let counter = 0;
let randomNumber = 0;

const getRandomNumber = (max) => {
  return Math.floor(Math.random() * max);
};

const removeFile = () => {
  return new Promise((res) => {
    fs.access(fileName, fs.F_OK, (err) => {
      if (err) return res(true);
      fs.unlink(fileName, () => {
        return res(true);
      });
    });
  });
};

const createFile = () => {
  if ( writeFile ) {
    content = `Pod is alive! 🤠
      Counter: ${counter}
      Random number: ${randomNumber}.
      ----------------------------------`;
    fs.writeFile(fileName, content, err => {
      if (err) {
        console.log('Error writing file'); 
        throw err;
      }
      setTimeout(() => {
        createFile();
      }, 1000);
    });
  } else {
    removeFile();
  }
};

const livenessCheck = () => {
  randomNumber = getRandomNumber(maxValue);
  if ( randomNumber === 7 ) {
    writeFile = false;
    removeFile()
      .then(() => {
        console.log('It is going to crash ☹️ ...\nRandom number is 7!');
      }); 
  } else {
    fs.access(fileName, fs.F_OK, (err) => {
      if (err) {
        console.log('Error, file does not exist! ☹️', err);
        writeFile = true;
        return;
      }
      counter += 1;
      console.log(content);
      setTimeout(() => {
        livenessCheck();
      }, 1000);
    });
  }
};

console.log(`Version: ${version}\n`);

createFile();
setTimeout(() => {
  livenessCheck();
}, 1000);
