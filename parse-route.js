const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');
const readline = require('readline/promises');

// Функция для безопасного чтения токена из файла .env
function loadEnv() {
    const envPath = path.join(__dirname, '.env');
    if (fs.existsSync(envPath)) {
        const envContent = fs.readFileSync(envPath, 'utf8');
        envContent.split(/\r?\n/).forEach(line => {
            const parts = line.split('=');
            if (parts.length === 2) {
                const key = parts[0].trim();
                const value = parts[1].trim();
                process.env[key] = value;
            }
        });
    }
}

loadEnv();
const MAPBOX_TOKEN = process.env.MAPBOX_TOKEN;

function parseGPX(content) {
    const regex = /<trkpt\s+lat="([^"]+)"\s+lon="([^"]+)">/g;
    let match;
    const points = [];
    while ((match = regex.exec(content)) !== null) {
        points.push({ x: parseFloat(match[2]), y: parseFloat(match[1]) });
    }
    return points;
}

function parseWaypoints(content) {
    const regex = /<wpt\s+lat="([^"]+)"\s+lon="([^"]+)">([\s\S]*?)<\/wpt>/g;
    let match;
    const waypoints = [];
    while ((match = regex.exec(content)) !== null) {
        const lat = parseFloat(match[1]);
        const lon = parseFloat(match[2]);
        const inner = match[3];
        
        const nameMatch = /<name>([^<]+)<\/name>/.exec(inner);
        const name = nameMatch ? nameMatch[1].trim() : `Waypoint (${lat.toFixed(4)}, ${lon.toFixed(4)})`;

        waypoints.push({ x: lon, y: lat, name });
    }

    return waypoints;
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

function downloadMapImage(minLon, minLat, maxLon, maxLat, destPath) {
    return new Promise((resolve) => {
        if (!MAPBOX_TOKEN) {
            console.log('Предупреждение: Токен MAPBOX_TOKEN не найден в файле .env. Скачивание карты пропущено.');
            return resolve();
        }

        const url = `https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/[${minLon},${minLat},${maxLon},${maxLat}]/800x600?access_token=${MAPBOX_TOKEN}`;
        
        console.log('Скачивание карты-подложки из Mapbox...');
        https.get(url, (res) => {
            if (res.statusCode !== 200) {
                console.error(`Ошибка скачивания карты: HTTP статус ${res.statusCode}`);
                res.resume();
                return resolve();
            }
            const fileStream = fs.createWriteStream(destPath);
            res.pipe(fileStream);
            fileStream.on('finish', () => {
                fileStream.close();
                console.log('Карта-подложка успешно сохранена как map.png!');
                resolve();
            });
        }).on('error', (err) => {
            console.error('Ошибка соединения при скачивании карты:', err.message);
            resolve();
        });
    });
}

function simplifyPoints(points, epsilon) {
    if (points.length <= 2) return points;

    let maxDist = 0;
    let index = 0;

    for (let i = 1; i < points.length - 1; i++) {
        const dist = perpendicularDistance(points[i], points[0], points[points.length - 1]);
        if (dist > maxDist) {
            maxDist = dist;
            index = i;
        }
    }

    if (maxDist > epsilon) {
        const left = simplifyPoints(points.slice(0, index + 1), epsilon);
        const right = simplifyPoints(points.slice(index, points.length), epsilon);
        return [...left.slice(0, -1), ...right];
    } else {
        return [points[0], points[points.length - 1]];
    }
}

function perpendicularDistance(point, start, end) {
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const length = Math.sqrt(dx * dx + dy * dy);
    const u = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (length * length);
    const closestX = start.x + u * dx;
    const closestY = start.y + u * dy;
    const closestPoint = { x: closestX, y: closestY };
    return Math.sqrt((point.x - closestX) ** 2 + (point.y - closestY) ** 2);
}

function filterGPSNoise(points, epsilon) {
    const filteredPoints = [points[0]];
    for (let i = 1; i < points.length - 1; i++) {
        const prevPoint = filteredPoints[filteredPoints.length - 1];
        const nextPoint = points[i + 1];
        const angle = Math.atan2(nextPoint.y - prevPoint.y, nextPoint.x - prevPoint.x);
        const prevAngle = Math.atan2(prevPoint.y - points[i].y, prevPoint.x - points[i].x);
        const angleDiff = Math.abs(angle - prevAngle);
        if (angleDiff > epsilon) {
            filteredPoints.push(points[i]);
        }
    }
    filteredPoints.push(points[points.length - 1]);
    return filteredPoints;
}

async function run() {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
    });

    try {
        const fileName = await rl.question('Введите имя файла (например, Banya Luka 10k.gpx): ');
        if (!fs.existsSync(fileName)) {
            console.log(`Ошибка: файл "${fileName}" не найден.`);
            rl.close();
            return;
        }

        const fileContent = fs.readFileSync(fileName, 'utf8');
        const ext = path.extname(fileName).toLowerCase();
        let rawPoints = [];
        let rawWaypoints = [];

        if (ext === '.gpx') {
            rawPoints = parseGPX(fileContent);
            rawWaypoints = parseWaypoints(fileContent);
        } else if (ext === '.svg') {
            rawPoints = parseSVG(fileContent);
        } else {
            console.log('Неподдерживаемый формат. Используйте .gpx или .svg');
            rl.close();
            return;
        }

        if (rawPoints.length === 0) {
            console.log('Координаты маршрута не найдены.');
            rl.close();
            return;
        }

        // Прореживание точек с использованием алгоритма Дугласа-Пекера
        const epsilon = 0.001; // Параметр для контроля точности
        rawPoints = simplifyPoints(rawPoints, epsilon);

        // Фильтрация GPS-шума
        rawPoints = filterGPSNoise(rawPoints, epsilon);

        // Автоматическое добавление всех точек без интерактивного опроса
        const selectedWaypoints = rawWaypoints;
        if (rawWaypoints.length > 0) {
            console.log(`\nАвтоматически добавлено точек из файла: ${rawWaypoints.length}`);
        }

        const lons = rawPoints.map(p => p.x);
        const lats = rawPoints.map(p => p.y);
        const minLon = Math.min(...lons), maxLon = Math.max(...lons);
        const minLat = Math.min(...lats), maxLat = Math.max(...lats);

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
        pointsToUse.forEach((p) => {
            const normX = Math.round(50 + ((p.x - minX) / (maxX - minX || 1)) * 700);
            const normY = ext === '.gpx'
                ? Math.round(550 - ((p.y - minY) / (maxY - minY || 1)) * 500)
                : Math.round(50 + ((p.y - minY) / (maxY - minY || 1)) * 500);

            rmlVertices.push(`      <CubicVertex radius="10" x="${normX}" y="${normY}" />`);
        });

        const rmlWaypoints = [];
        selectedWaypoints.forEach((wpt, index) => {
            const wptX = Math.round(50 + ((wpt.x - minX) / (maxX - minX || 1)) * 700);
            const wptY = ext === '.gpx'
                ? Math.round(550 - ((wpt.y - minY) / (maxY - minY || 1)) * 500)
                : Math.round(50 + ((wpt.y - minY) / (maxY - minY || 1)) * 500);

            rmlWaypoints.push(`    <Node x="${wptX}" y="${wptY}" name="${wpt.name}" id="0:${500 + index}">\n      <!-- Подготовлено для анимации Fade In + Scale In -->\n    </Node>`);
        });

        const baseName = path.basename(fileName, ext).trim();
        const projectFolder = baseName;

        fs.mkdirSync(projectFolder, { recursive: true });
        
        await downloadMapImage(minLon, minLat, maxLon, maxLat, path.join(projectFolder, 'map.png'));

        const yamlPath = path.join(projectFolder, 'rive.yaml');
        if (!fs.existsSync(yamlPath)) {
            fs.writeFileSync(yamlPath, `name: ${baseName}\n`);
        }

        const rmlTemplate = `<?xml version="1.0" encoding="UTF-8"?>
<Rive version="1" kind="fragment">
  <Artboard defaultStateMachineId="0:7" spaceId="17:1" width="800" height="600" styleId="0:0" name="RouteArtboard" id="0:238">
    <NestedArtboard artboardId="3:38" x="524.5" y="167.5" rotation="0.90279633" name="Car" complexDependency="true" id="3:459">
      <NestedStateMachine animationId="3:453" id="3:460"/>
      <FollowPathConstraint targetId="0:239" id="3:877"/>
    </NestedArtboard>
    <Shape name="RoutePath" id="0:239">
      <PointsPath id="0:240">
${rmlVertices.join('\n')}
      </PointsPath>
      <Stroke thickness="9" cap="round" id="0:3">
        <SolidColor colorValue="FFFFFFFF" name="WhiteCasing" id="0:236" />
        <TrimPath end="1" modeValue="sequential" name="TrimWhite" id="0:4" />
      </Stroke>
      <Stroke thickness="3" cap="round" id="0:5">
        <SolidColor colorValue="FF00A8D6" name="BlueLine" id="0:237" />
        <TrimPath end="1" modeValue="sequential" name="TrimBlue" id="0:6" />
      </Stroke>
    </Shape>
    
${rmlWaypoints.join('\n')}

    <StateMachine name="State Machine 1" id="0:7">
      <StateMachineLayer name="Layer 1" id="0:8">
        <AnyState x="200" y="-120" id="0:85"/>
        <ExitState x="400" y="-120" id="0:86"/>
        <EntryState id="0:87">
          <StateTransition stateToId="0:88" id="3:30"/>
        </EntryState>
        <AnimationState animationId="3:1" x="300" id="0:88"/>
      </StateMachineLayer>
    </StateMachine>
    <LinearAnimation duration="360" loopValue="loop" name="route" id="3:1">
      <KeyedObject objectId="0:6" id="3:16">
        <KeyedProperty property="end" id="3:17">
          <KeyFrameDouble interpolationType="cubic" id="3:18">
            <CubicEaseInterpolator x1="0.5" x2="0" y2="0.5" id="3:26"/>
          </KeyFrameDouble>
          <KeyFrameDouble value="1" interpolationType="cubic" frame="300" id="3:23">
            <CubicEaseInterpolator x1="0.5" x2="0" y2="0.5" id="3:24"/>
          </KeyFrameDouble>
        </KeyedProperty>
      </KeyedObject>
      <KeyedObject objectId="0:4" id="3:19">
        <KeyedProperty property="end" id="3:20">
          <KeyFrameDouble interpolationType="cubic" id="3:21">
            <CubicEaseInterpolator x1="0.5" x2="0" y2="0.5" id="3:29"/>
          </KeyFrameDouble>
          <KeyFrameDouble value="1" interpolationType="cubic" frame="300" id="3:22">
            <CubicEaseInterpolator x1="0.5" x2="0" y2="0.5" id="3:25"/>
          </KeyFrameDouble>
        </KeyedProperty>
      </KeyedObject>
      <KeyedObject objectId="3:877" id="3:878">
        <KeyedProperty property="distance" id="3:879">
          <KeyFrameDouble interpolationType="cubic" id="3:880">
            <CubicEaseInterpolator x1="0.5" x2="0" y2="0.5" id="3:883"/>
          </KeyFrameDouble>
          <KeyFrameDouble value="1" interpolationType="linear" frame="300" id="3:881"/>
        </KeyedProperty>
      </KeyedObject>
    </LinearAnimation>
  </Artboard>
  <Artboard originX="0.5" originY="0.5" defaultStateMachineId="3:453" isComponent="true" spaceId="17:1" width="34" height="19" styleId="3:39" x="900" name="Car" id="3:38">
    <Node x="-0.12497568" y="-0.25060511" rotation="1.110223e-16" scaleX="0.25" scaleY="0.25" id="3:874">
      <Shape x="22.611509" y="0.0013960004" rotation="1.570796" scaleX="0.99999994" scaleY="0.99999994" name="Glass↑" id="3:95">
        <PointsPath isClosed="true" name="Path" id="3:96">
          <CubicDetachedVertex outRotation="-0.22389977" outDistance="4.0849648" x="-17.327999" y="-9.0535002" name="Component" id="3:97"/>
          <CubicDetachedVertex inRotation="3.1415927" inDistance="7.8319998" outDistance="7.8319998" x="1.1368684e-13" y="-10.8885" name="Component" id="3:98"/>
          <CubicDetachedVertex inRotation="-2.9177473" inDistance="4.0859399" outRotation="0.22395478" outDistance="2.6881313" x="17.327999" y="-9.0535002" name="Component" id="3:99"/>
          <CubicDetachedVertex inRotation="-1.3632618" inDistance="2.6886942" x="21.007" y="-3.1754999" name="Component" id="3:100"/>
          <CubicDetachedVertex outRotation="1.7783523" outDistance="2.586513" x="18.940001" y="6.6424999" name="Component" id="3:101"/>
          <CubicDetachedVertex inRotation="0.080122903" inDistance="2.5862973" outRotation="-3.0613499" outDistance="3.3808787" x="13.456" y="10.6815" name="Component" id="3:102"/>
          <CubicDetachedVertex inDistance="5.1919999" outRotation="3.1415927" outDistance="5.1919999" y="10.1115" name="Component" id="3:103"/>
          <CubicDetachedVertex inRotation="-0.08024276" inDistance="3.3808787" outRotation="3.0615008" outDistance="2.5872939" x="-13.456" y="10.6815" name="Component" id="3:104"/>
          <CubicDetachedVertex inRotation="1.3632404" inDistance="2.586513" x="-18.940001" y="6.6424999" name="Component" id="3:105"/>
          <CubicDetachedVertex outRotation="-1.7783309" outDistance="2.6886942" x="-21.007" y="-3.1754999" name="Component" id="3:106"/>
          <CubicDetachedVertex inRotation="2.9176378" inDistance="2.6881313" x="-17.327999" y="-9.0535002" name="Component" id="3:107"/>
        </PointsPath>
        <Fill name="Fill 1" id="3:108">
          <SolidColor colorValue="FF000000" name="Component" id="3:109"/>
        </Fill>
      </Shape>
      <Shape x="-55.247849" y="0.0015144348" rotation="1.570796" scaleX="0.99999994" scaleY="0.99999994" name="Glass ↓" id="3:110">
        <PointsPath isClosed="true" isClockwise="false" name="Path" id="3:111">
          <CubicDetachedVertex outRotation="0.16150978" outDistance="3.7498014" x="-13.602" y="5.5809999" name="Component" id="3:112"/>
          <CubicDetachedVertex inRotation="3.1415927" inDistance="5.27" outDistance="5.2709999" x="-0.001" y="6.6589999" name="Component" id="3:113"/>
          <CubicDetachedVertex inRotation="2.9801257" inDistance="3.7507882" outRotation="-0.16158502" outDistance="2.9524601" x="13.602" y="5.5809999" name="Component" id="3:114"/>
          <CubicDetachedVertex inRotation="1.2284787" inDistance="2.9522943" x="17.15" y="-0.708" name="Component" id="3:115"/>
          <CubicDetachedVertex outRotation="-1.9130335" outDistance="2.2229152" x="16.257999" y="-3.214" name="Component" id="3:116"/>
          <CubicDetachedVertex inRotation="-0.045893013" inDistance="2.223341" outRotation="3.0953114" outDistance="3.0692866" x="11.255" y="-6.5570002" name="Component" id="3:117"/>
          <CubicDetachedVertex inDistance="3.7609999" outRotation="3.1415927" outDistance="3.76" x="-0.001" y="-6.2480001" name="Component" id="3:118"/>
          <CubicDetachedVertex inRotation="0.046281345" inDistance="3.0692866" outRotation="-3.095679" outDistance="2.222342" x="-11.256" y="-6.5570002" name="Component" id="3:119"/>
          <CubicDetachedVertex inRotation="-1.2285591" inDistance="2.2229152" x="-16.257999" y="-3.214" name="Component" id="3:120"/>
          <CubicDetachedVertex outRotation="1.913114" outDistance="2.9522943" x="-17.15" y="-0.708" name="Component" id="3:121"/>
          <CubicDetachedVertex inRotation="-2.980062" inDistance="2.9534471" x="-13.602" y="5.5809999" name="Component" id="3:122"/>
        </PointsPath>
        <Fill name="Fill 1" id="3:123">
          <SolidColor colorValue="FF000000" name="Component" id="3:124"/>
        </Fill>
      </Shape>
      <Shape x="-12.791924" y="-23.726511" rotation="1.570796" scaleX="0.99999994" scaleY="0.99999994" name="Glass ←" id="3:125">
        <PointsPath isClosed="true" isClockwise="false" name="Path" id="3:126">
          <CubicDetachedVertex outRotation="-1.6162196" outDistance="8.8090858" x="2.7290001" y="-13.792" name="Component" id="3:127"/>
          <CubicDetachedVertex inRotation="1.3439975" inDistance="6.6708322" outRotation="1.5810215" outDistance="33.25174" x="-2.2709999" y="-40.292" name="Component" id="3:128"/>
          <CubicDetachedVertex inRotation="-1.6251754" inDistance="12.437385" outRotation="1.5158778" outDistance="1.5303072" x="-2.553" y="38.312" name="Component" id="3:129"/>
          <CubicDetachedVertex inRotation="2.0446775" inDistance="1.5295506" outRotation="-1.0970179" outDistance="3.4432743" x="-0.31600001" y="38.931" name="Component" id="3:130"/>
          <CubicDetachedVertex inRotation="1.5707964" inDistance="2.523" outRotation="-1.5707964" outDistance="4.5" x="2.7279999" y="28.708" name="Component" id="3:131"/>
          <CubicDetachedVertex inRotation="1.5253731" inDistance="11.011357" x="2.7290001" y="-13.792" name="Component" id="3:132"/>
        </PointsPath>
        <Fill name="Fill 1" id="3:133">
          <SolidColor colorValue="FF000000" name="Component" id="3:134"/>
        </Fill>
      </Shape>
      <Shape x="-12.791986" y="23.729904" rotation="1.570796" scaleX="0.99999994" scaleY="0.99999994" name="Glass →" id="3:135">
        <PointsPath isClosed="true" name="Path" id="3:136">
          <CubicDetachedVertex outRotation="-1.5253731" outDistance="8.8090858" x="-2.7284999" y="-13.792" name="Component" id="3:137"/>
          <CubicDetachedVertex inRotation="1.7977413" inDistance="6.6710567" outRotation="1.5606012" outDistance="33.251728" x="2.2715001" y="-40.292" name="Component" id="3:138"/>
          <CubicDetachedVertex inRotation="-1.5164173" inDistance="12.437385" outRotation="1.6250623" outDistance="1.5302526" x="2.5525" y="38.312" name="Component" id="3:139"/>
          <CubicDetachedVertex inRotation="1.0969151" inDistance="1.5295506" outRotation="-2.0443163" outDistance="3.4428179" x="0.31549999" y="38.931" name="Component" id="3:140"/>
          <CubicDetachedVertex inRotation="1.5707964" inDistance="2.523" outRotation="-1.5707964" outDistance="4.5" x="-2.7284999" y="28.708" name="Component" id="3:141"/>
          <CubicDetachedVertex inRotation="1.6162196" inDistance="11.011357" x="-2.7284999" y="-13.792" name="Component" id="3:142"/>
        </PointsPath>
        <Fill name="Fill 1" id="3:143">
          <SolidColor colorValue="FF000000" name="Component" id="3:144"/>
        </Fill>
      </Shape>
      <Shape x="1.4579855e-06" y="0.0020053983" rotation="1.570796" scaleX="0.99999994" scaleY="0.99999994" name="Body" id="3:145">
        <PointsPath isClosed="true" isClockwise="false" name="Path" id="3:146">
          <CubicDetachedVertex inRotation="-2.1237357" inDistance="2.3972237" outRotation="1.0177649" outDistance="11.137146" x="-31.265499" y="57.200001" name="Component" id="3:147"/>
          <CubicDetachedVertex inRotation="3.1415927" inDistance="17.232" outDistance="17.231001" x="0.00050000002" y="67.5" name="Component" id="3:148"/>
          <CubicDetachedVertex inRotation="2.1238277" inDistance="11.137146" outRotation="-1.018212" outDistance="2.3966985" x="31.265499" y="57.200001" name="Component" id="3:149"/>
          <CubicDetachedVertex inRotation="1.5707964" inDistance="2.3970001" x="32.9995" y="50.359001" name="Component" id="3:150"/>
          <CubicDetachedVertex outRotation="-1.5707964" outDistance="1.436" x="32.9995" y="28.676001" name="Component" id="3:151"/>
          <CubicDetachedVertex inRotation="1.1660875" inDistance="1.4349167" outRotation="-1.9757247" outDistance="3.5892613" x="32.142502" y="24.5" name="Component" id="3:152"/>
          <CubicDetachedVertex inRotation="1.5707964" inDistance="3.589" x="30.0005" y="14.06" name="Component" id="3:153"/>
          <CubicDetachedVertex outRotation="-1.5707964" outDistance="3.589" x="30.0005" y="-15.06" name="Component" id="3:154"/>
          <CubicDetachedVertex inRotation="1.9757247" inDistance="3.5892613" outRotation="-1.1663618" outDistance="1.435836" x="32.142502" y="-25.5" name="Component" id="3:155"/>
          <CubicDetachedVertex inRotation="1.5707964" inDistance="1.436" x="32.9995" y="-29.676001" name="Component" id="3:156"/>
          <CubicDetachedVertex outRotation="-1.5707964" outDistance="1.946" x="32.9995" y="-52.556" name="Component" id="3:157"/>
          <CubicDetachedVertex inRotation="1.0065886" inDistance="1.9467167" outRotation="-2.1350935" outDistance="9.6181526" x="31.6875" y="-58.132" name="Component" id="3:158"/>
          <CubicDetachedVertex inDistance="14.099" outRotation="3.1415927" outDistance="14.099" x="-0.00050000002" y="-67.5" name="Component" id="3:159"/>
          <CubicDetachedVertex inRotation="-1.0064992" inDistance="9.6181526" outRotation="2.135004" outDistance="1.9467167" x="-31.688499" y="-58.132" name="Component" id="3:160"/>
          <CubicDetachedVertex inRotation="-1.5707964" inDistance="1.946" x="-32.9995" y="-52.556" name="Component" id="3:161"/>
          <CubicDetachedVertex outRotation="1.5707964" outDistance="1.436" x="-32.9995" y="-29.676001" name="Component" id="3:162"/>
          <CubicDetachedVertex inRotation="-1.975871" inDistance="1.4362298" outRotation="1.1661241" outDistance="3.5888674" x="-32.142502" y="-25.5" name="Component" id="3:163"/>
          <CubicDetachedVertex inRotation="-1.5707964" inDistance="3.589" x="-30.0005" y="-15.06" name="Component" id="3:164"/>
          <CubicDetachedVertex outRotation="1.5707964" outDistance="3.589" x="-30.0005" y="14.06" name="Component" id="3:165"/>
          <CubicDetachedVertex inRotation="-1.1661241" inDistance="3.5888674" outRotation="1.9761455" outDistance="1.4353107" x="-32.142502" y="24.5" name="Component" id="3:166"/>
          <CubicDetachedVertex inRotation="-1.5707964" inDistance="1.436" x="-32.9995" y="28.676001" name="Component" id="3:167"/>
          <CubicDetachedVertex outRotation="1.5707964" outDistance="2.3970001" x="-32.9995" y="50.359001" name="Component" id="3:168"/>
        </PointsPath>
        <Fill name="Fill 1" id="3:169">
          <SolidColor colorValue="FF00A8D6" name="Component" id="3:170"/>
        </Fill>
      </Shape>
    </Node>
  </Artboard>
  <ComponentAsset artboardId="3:38" name="Artboard 1" id="3:458"/>
  <Space name="Space 1" id="17:1"/>
</Rive>`;
        fs.writeFileSync(path.join(projectFolder, 'scene.rml'), rmlTemplate);
        console.log(`Структура проекта обновлена в папке ${projectFolder}/`);

        console.log('Сборка .riv файла...');
        try {
            execSync('xvfb-run rive . --once', { cwd: projectFolder, stdio: 'inherit' });
        } catch (buildErr) {
            console.error('Ошибка сборки Rive. Проверьте синтаксис RML.');
        }

        console.log('Создание коммита в Git...');
        execSync('git add "../parse-route.js" "."', { cwd: path.join(__dirname, projectFolder), stdio: 'inherit' });
        execSync(`git commit -m "Generate RML, download map background and parse waypoints: ${projectFolder}"`, { cwd: path.join(__dirname, projectFolder), stdio: 'inherit' });

        console.log('Готово!');

    } catch (err) {
        console.error('Ошибка:', err);
    } finally {
        rl.close();
    }
}

run();
