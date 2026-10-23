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
    while ((pathMatch = pathRegex.exec(content)) !== null) {
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
    const fileName = await readline.question('Введите имя файла (например, route.gpx или mykonos-tours.svg): ');
    
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
    if (rawPoints.length > 200) {
      const step = Math.ceil(rawPoints.length / 200);
      pointsToUse = rawPoints.filter((_, index) => index % step === 0);
    }

    const xs = pointsToUse.map(p => p.x);
    const ys = pointsToUse.map(p => p.y);
    const minX = Math.min(...xs), maxX = Math.max(...xs);
    const minY = Math.min(...ys), maxY = Math.max(...ys);

    const rmlVertices = [];
    const rmlKeyFramesTrim = [];

    pointsToUse.forEach((p, index) => {
      const normX = Math.round(50 + ((p.x - minX) / (maxX - minX || 1)) * 700);
      const normY = ext === '.gpx'
        ? Math.round(550 - ((p.y - minY) / (maxY - minY || 1)) * 500)
        : Math.round(50 + ((p.y - minY) / (maxY - minY || 1)) * 500);
      const frame = index * 10;
      
      rmlVertices.push(`        <StraightVertex x="${normX}" y="${normY}" />`);

      const trimProgress = Math.round((index / (pointsToUse.length - 1)) * 100);
      rmlKeyFramesTrim.push(`        <KeyFrameDouble frame="${frame}" value="${trimProgress}" />`);
    });

    const baseName = path.basename(fileName, ext);
    const projectFolder = baseName;
    
    fs.mkdirSync(projectFolder, { recursive: true });
    fs.writeFileSync(path.join(projectFolder, 'rive.yaml'), `name: ${baseName}\n`);

    const rmlTemplate = `<?xml version="1.0" encoding="UTF-8"?>
<Rive kind="fragment" version="1">
  <Artboard name="RouteArtboard" width="800" height="600">
    <Shape name="RoutePath">
      <PointsPath>
${rmlVertices.join('\n')}
      </PointsPath>
      <Stroke thickness="6">
        <SolidColor colorRed="231" colorGreen="76" colorBlue="60" />
        <TrimPath start="0" end="0" name="RouteTrim" modeValue="1" id="0:3" />
      </Stroke>
    </Shape>

    <Animation name="drive">
      <KeyedObject objectId="0:3">
${rmlKeyFramesTrim.join('\n')}
      </KeyedObject>
    </Animation>
  </Artboard>
</Rive>`;

    fs.writeFileSync(path.join(projectFolder, 'scene.rml'), rmlTemplate);
    console.log(`Структура проекта обновлена в папке ${projectFolder}/`);

    console.log('Запуск верификации...');
    execSync(`xvfb-run rive . --verify`, { cwd: path.join(__dirname, projectFolder), stdio: 'inherit' });
    console.log(`Готово! Верификация пройдена успешно.`);

  } catch (err) {
    console.error('Ошибка:', err);
  } finally {
    readline.close();
  }
}

run();