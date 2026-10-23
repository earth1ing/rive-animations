const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const readline = require('readline/promises').createInterface({
  input: process.stdin,
  output: process.stdout,
});

function parseGPX(content) {
  const regex = /<trkpt\s+lat="([^"]+)"\s+lon="([^"]+)">/g;
  let match;
  const points = [];
  while ((match = regex.exec(content)) !== null) {
    points.push({ x: parseFloat(match[2]), y: parseFloat(match[1]) });
  }
  return points;
}

function parseSVG(content) {
  const points = [];
  const polyRegex = /points="([^"]+)"/g;
  let polyMatch;
  while ((polyMatch = polyRegex.exec(content)) !== null) {
    const rawPairs = polyMatch[1].trim().split(/[\s,]+/);
    for (let i = 0; i < rawPairs.length; i += 2) {
      if (rawPairs[i] && rawPairs[i + 1]) {
        points.push({ x: parseFloat(rawPairs[i]), y: parseFloat(rawPairs[i + 1]) });
      }
    }
  }
  if (points.length === 0) {
    const pathRegex = /d="([^"]+)"/g;
    let pathMatch;
    while ((pathMatch = pathMatch.exec(content)) !== null) {
      const numbers = pathMatch[1].match(/[-+]?[0-9]*\.?[0-9]+/g);
      if (numbers) {
        for (let i = 0; i < numbers.length; i += 2) {
          if (numbers[i] && numbers[i + 1]) {
            points.push({ x: parseFloat(numbers[i]), y: parseFloat(numbers[i + 1]) });
          }
        }
      }
    }
  }
  return points;
}

async function run() {
  try {
    const fileName = await readline.question('Введите имя файла (например, Banya Luka 10k.gpx): ');
    
    if (!fs.existsSync(fileName)) {
      console.log(`Ошибка: файл "${fileName}" не найден.`);
      readline.close();
      return;
    }

    const fileContent = fs.readFileSync(fileName, 'utf8');
    const ext = path.extname(fileName).toLowerCase();
    let rawPoints = [];

    if (ext === '.gpx') rawPoints = parseGPX(fileContent);
    else if (ext === '.svg') rawPoints = parseSVG(fileContent);
    else {
      console.log('Неподдерживаемый формат. Используйте .gpx или .svg');
      readline.close();
      return;
    }

    if (rawPoints.length === 0) {
      console.log('Координаты не найдены.');
      readline.close();
      return;
    }

    let pointsToUse = rawPoints;
    if (rawPoints.length > 150) {
      const step = Math.ceil(rawPoints.length / 150);
      pointsToUse = rawPoints.filter((_, index) => index % step === 0);
    }

    const xs = pointsToUse.map(p => p.x);
    const ys = pointsToUse.map(p => p.y);
    const minX = Math.min(...xs), maxX = Math.max(...xs);
    const minY = Math.min(...ys), maxY = Math.max(...ys);

    const rmlVertices = [];
    const rmlKeyFramesTrim = [];
    const totalFrames = 300; // 5 секунд при 60 fps

    pointsToUse.forEach((p, index) => {
      const normX = Math.round(50 + ((p.x - minX) / (maxX - minX || 1)) * 700);
      const normY = ext === '.gpx'
        ? Math.round(550 - ((p.y - minY) / (maxY - minY || 1)) * 500)
        : Math.round(50 + ((p.y - minY) / (maxY - minY || 1)) * 500);
      
      const frame = Math.round((index / (pointsToUse.length - 1)) * totalFrames);
      
      rmlVertices.push(`        <StraightVertex x="${normX}" y="${normY}" />`);

      const trimProgress = Math.round((index / (pointsToUse.length - 1)) * 100);
      rmlKeyFramesTrim.push(`        <KeyFrameDouble frame="${frame}" value="${trimProgress}" />`);
    });

    const baseName = path.basename(fileName, ext).trim();
    const projectFolder = baseName;
    
    fs.mkdirSync(projectFolder, { recursive: true });
    fs.writeFileSync(path.join(projectFolder, 'rive.yaml'), `name: ${baseName}\n`);

    const rmlTemplate = `<?xml version="1.0" encoding="UTF-8"?>
<Rive kind="fragment" version="1">
  <Artboard defaultStateMachineId="0:7" name="RouteArtboard" width="800" height="600">
    <Shape name="RoutePath">
      <PointsPath>
${rmlVertices.join('\n')}
      </PointsPath>
      <Stroke thickness="9" id="0:3">
        <SolidColor colorRed="255" colorGreen="255" colorBlue="255" name="WhiteCasing" />
        <TrimPath start="0" end="0" name="TrimWhite" modeValue="1" id="0:4" />
      </Stroke>
      <Stroke thickness="3" id="0:5">
        <SolidColor colorRed="0" colorGreen="168" colorBlue="214" name="BlueLine" />
        <TrimPath start="0" end="0" name="TrimBlue" modeValue="1" id="0:6" />
      </Stroke>
    </Shape>

    <Animation name="drive">
      <KeyedObject objectId="0:4">
${rmlKeyFramesTrim.join('\n')}
      </KeyedObject>
      <KeyedObject objectId="0:6">
${rmlKeyFramesTrim.join('\n')}
      </KeyedObject>
    </Animation>

    <StateMachine name="State Machine 1" id="0:7">
      <StateMachineLayer name="Layer 1" id="0:8">
        <AnyState x="200" y="-120" id="0:85"/>
        <ExitState x="400" y="-120" id="0:86"/>
        <EntryState id="0:87"/>
      </StateMachineLayer>
    </StateMachine>
  </Artboard>
</Rive>`;

    fs.writeFileSync(path.join(projectFolder, 'scene.rml'), rmlTemplate);
    console.log(`Структура проекта обновлена в папке ${projectFolder}/`);

    console.log('Сборка .riv файла...');
    try {
      // timeout прерывает watch-режим через 3 секунды после успешной сборки
      execSync(`timeout 3 xvfb-run rive .`, { cwd: path.join(__dirname, projectFolder), stdio: 'ignore' });
    } catch (e) {
      // Игнорируем код выхода таймаута (124), так как сборка успевает завершиться за миллисекунды
    }
    console.log('Сборка завершена.');

    console.log('Пуш проекта в Rive Editor...');
    execSync(`xvfb-run rive push`, { cwd: path.join(__dirname, projectFolder), stdio: 'inherit' });

    console.log('Создание коммита в Git...');
    execSync(`git add "../parse-route.js" "."`, { cwd: path.join(__dirname, projectFolder), stdio: 'inherit' });
    execSync(`git commit -m "Build, push and update Rive project: ${projectFolder}"`, { stdio: 'inherit' });
    console.log(`Готово! Всё собрано, запушено и закоммичено.`);

  } catch (err) {
    console.error('Ошибка:', err);
  } finally {
    readline.close();
  }
}

run();