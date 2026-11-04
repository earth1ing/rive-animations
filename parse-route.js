const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');
const readline = require('readline/promises');

function loadEnv() {
    const envPath = path.join(__dirname, '.env');
    if (fs.existsSync(envPath)) {
        const envContent = fs.readFileSync(envPath, 'utf8');
        envContent.split(/\r?\n/).forEach(line => {
            const parts = line.split('=');
            if (parts.length === 2) {
                process.env[parts[0].trim()] = parts[1].trim();
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
        const lat = parseFloat(match[1]), lon = parseFloat(match[2]);
        const nameMatch = /<name>([^<]+)<\/name>/.exec(match[3]);
        const name = nameMatch ? nameMatch[1].trim() : `Waypoint (${lat.toFixed(4)}, ${lon.toFixed(4)})`;
        waypoints.push({ x: lon, y: lat, name });
    }
    return waypoints;
}

function downloadMapImage(minLon, minLat, maxLon, maxLat, destPath) {
    return new Promise((resolve) => {
        if (!MAPBOX_TOKEN) {
            console.log('Токен MAPBOX_TOKEN не найден. Скачивание карты пропущено.');
            return resolve();
        }
        const url = `https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/[${minLon},${minLat},${maxLon},${maxLat}]/800x600?access_token=${MAPBOX_TOKEN}`;
        console.log('Скачивание карты из Mapbox...');
        https.get(url, (res) => {
            if (res.statusCode !== 200) {
                console.error(`Ошибка скачивания карты: HTTP status ${res.statusCode}`);
                res.resume();
                return resolve();
            }
            const fileStream = fs.createWriteStream(destPath);
            res.pipe(fileStream);
            fileStream.on('finish', () => {
                fileStream.close();
                console.log('Карта успешно сохранена как map.png');
                resolve();
            });
        }).on('error', (err) => {
            console.error('Ошибка соединения Mapbox:', err.message);
            resolve();
        });
    });
}

function simplifyPoints(points, epsilon) {
    if (points.length <= 2) return points;
    let maxDist = 0, index = 0;
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
    }
    return [points[0], points[points.length - 1]];
}

function perpendicularDistance(point, start, end) {
    const dx = end.x - start.x, dy = end.y - start.y;
    const length = Math.sqrt(dx * dx + dy * dy);
    const u = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (length * length);
    return Math.sqrt((point.x - (start.x + u * dx)) ** 2 + (point.y - (start.y + u * dy)) ** 2);
}

function filterGPSNoise(points, epsilon) {
    const filteredPoints = [points[0]];
    for (let i = 1; i < points.length - 1; i++) {
        const prevPoint = filteredPoints[filteredPoints.length - 1];
        const nextPoint = points[i + 1];
        const angle = Math.atan2(nextPoint.y - prevPoint.y, nextPoint.x - prevPoint.x);
        const prevAngle = Math.atan2(prevPoint.y - points[i].y, prevPoint.x - points[i].x);
        if (Math.abs(angle - prevAngle) > epsilon) {
            filteredPoints.push(points[i]);
        }
    }
    filteredPoints.push(points[points.length - 1]);
    return filteredPoints;
}

async function run() {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    try {
        const fileName = await rl.question('Введите имя GPX файла (например, Banya Luka 10k.gpx): ');
        if (!fs.existsSync(fileName)) {
            console.log(`Ошибка: файл "${fileName}" не найден.`);
            return;
        }

        const fileContent = fs.readFileSync(fileName, 'utf8');
        let rawPoints = parseGPX(fileContent);
        let rawWaypoints = parseWaypoints(fileContent);

        if (rawPoints.length === 0) {
            console.log('Маршрут не найден.');
            return;
        }

        const epsilon = 0.001;
        rawPoints = filterGPSNoise(simplifyPoints(rawPoints, epsilon), epsilon);

        const lons = rawPoints.map(p => p.x), lats = rawPoints.map(p => p.y);
        const minLon = Math.min(...lons), maxLon = Math.max(...lons);
        const minLat = Math.min(...lats), maxLat = Math.max(...lats);

        let pointsToUse = rawPoints;
        if (rawPoints.length > 150) {
            const step = Math.ceil(rawPoints.length / 150);
            pointsToUse = rawPoints.filter((_, index) => index % step === 0);
        }

        const xs = pointsToUse.map(p => p.x), ys = pointsToUse.map(p => p.y);
        const minX = Math.min(...xs), maxX = Math.max(...xs);
        const minY = Math.min(...ys), maxY = Math.max(...ys);

        const avgLat = lats.reduce((sum, lat) => sum + lat, 0) / lats.length;
        const latCorrection = Math.cos(avgLat * (Math.PI / 180));

        const spanX = (maxX - minX) * latCorrection;
        const spanY = maxY - minY;

        const scaleX = 700 / (spanX || 1);
        const scaleY = 500 / (spanY || 1);
        const scale = Math.min(scaleX, scaleY);

        const offsetX = 50 + (700 - spanX * scale) / 2;
        const offsetY = 50 + (500 - spanY * scale) / 2;

        const rmlVertices = pointsToUse.map((p, idx) => {
            const normX = Math.round(offsetX + (p.x - minX) * latCorrection * scale);
            const normY = Math.round(550 - (offsetY - 50 + (p.y - minY) * scale));
            return `                <StraightVertex radius="10" x="${normX}" y="${normY}" id="0:${884 + idx}"/>`;
        });

        const rmlWaypoints = rawWaypoints.map((wpt, index) => {
            const wptX = Math.round(offsetX + (wpt.x - minX) * latCorrection * scale);
            const wptY = Math.round(550 - (offsetY - 50 + (wpt.y - minY) * scale));
            return `        <Node x="${wptX}" y="${wptY}" name="${wpt.name}" id="0:${500 + index}"/>`;
        });

        const padding = 50;
        const targetWidth = 700, targetHeight = 500;
        const lonPadding = (maxLon - minLon) * (padding / targetWidth);
        const latPadding = (maxLat - minLat) * (padding / targetHeight);

        const baseName = path.basename(fileName, path.extname(fileName)).trim();
        const projectFolder = baseName;
        fs.mkdirSync(projectFolder, { recursive: true });

        await downloadMapImage(minLon - lonPadding, minLat - latPadding, maxLon + lonPadding, maxLat + latPadding, path.join(projectFolder, 'map.png'));

        const yamlPath = path.join(projectFolder, 'rive.yaml');
        if (!fs.existsSync(yamlPath)) fs.writeFileSync(yamlPath, `name: ${baseName}\n`);

        // Читаем внешний шаблон разметки
        const templatePath = path.join(__dirname, 'route-template.rml');
        let rmlTemplate = fs.readFileSync(templatePath, 'utf8');

        // Подставляем сгенерированные вершины и вейпоинты в шаблон
        rmlTemplate = rmlTemplate
            .replace('{{RML_VERTICES}}', rmlVertices.join('\n'))
            .replace('{{RML_WAYPOINTS}}', rmlWaypoints.join('\n'));

        // Записываем итоговый файл сцены в папку проекта
        fs.writeFileSync(path.join(projectFolder, 'scene.rml'), rmlTemplate);
        console.log(`Проект обновлен в ${projectFolder}/`);

        try {
            execSync('xvfb-run rive . --once', { cwd: projectFolder, stdio: 'inherit' });
            console.log('Сборка Rive прошла успешно!');
        } catch (buildErr) {
            console.error('Ошибка сборки Rive.');
        }

        execSync('git add "../parse-route.js" "."', { cwd: path.join(__dirname, projectFolder), stdio: 'inherit' });
        execSync(`git commit -m "Generate RML, download map background: ${projectFolder}"`, { cwd: path.join(__dirname, projectFolder), stdio: 'inherit' });
        console.log('Готово!');

    } catch (err) {
        console.error('Ошибка:', err);
    } finally {
        rl.close();
    }
}

run();