const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');
const readline = require('readline/promises');
const sharp = require('sharp');

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

// Функция обработки и масштабирования изображений (меньшая сторона = 400px)
async function processWaypointImage(waypointName, projectFolder) {
    const imgDir = path.join(__dirname, 'img');
    const extensions = ['.png', '.jpg', '.jpeg', '.webp'];
    let sourceImgPath = null;
    let extFound = '';

    for (const ext of extensions) {
        const testPath = path.join(imgDir, `${waypointName}${ext}`);
        if (fs.existsSync(testPath)) {
            sourceImgPath = testPath;
            extFound = ext;
            break;
        }
    }

    if (!sourceImgPath) {
        console.log(`Предупреждение: картинка для точки "${waypointName}" в папке img/ не найдена.`);
        return null;
    }

    const destImgName = `${waypointName}${extFound}`;
    const destImgPath = path.join(projectFolder, destImgName);

    try {
        const metadata = await sharp(sourceImgPath).metadata();
        const width = metadata.width;
        const height = metadata.height;

        let resizeOptions = {};
        if (width < height) {
            resizeOptions = { width: 400 };
        } else {
            resizeOptions = { height: 400 };
        }

        await sharp(sourceImgPath)
            .resize(resizeOptions)
            .toFile(destImgPath);

        console.log(`Изображение для "${waypointName}" масштабировано и сохранено.`);
        return { fileName: destImgName, format: extFound.replace('.', '') };
    } catch (err) {
        console.error(`Ошибка обработки изображения для ${waypointName}:`, err.message);
        return null;
    }
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

function filterGPSNoise(points, minAngleThreshold = 0.15) {
    if (points.length <= 2) return points;
    const filteredPoints = [points[0]];

    for (let i = 1; i < points.length - 1; i++) {
        const pPrev = filteredPoints[filteredPoints.length - 1];
        const pCurr = points[i];
        const pNext = points[i + 1];

        const dx1 = pCurr.x - pPrev.x;
        const dy1 = pCurr.y - pPrev.y;
        const dx2 = pNext.x - pCurr.x;
        const dy2 = pNext.y - pCurr.y;

        const len1 = Math.sqrt(dx1 * dx1 + dy1 * dy1);
        const len2 = Math.sqrt(dx2 * dx2 + dy2 * dy2);

        if (len1 < 0.00001) continue;

        if (len2 > 0.00001) {
            const dot = dx1 * dx2 + dy1 * dy2;
            const cosTheta = Math.max(-1, Math.min(1, dot / (len1 * len2)));
            const angle = Math.acos(cosTheta);

            if (angle > minAngleThreshold || len1 > 0.0005) {
                filteredPoints.push(pCurr);
            }
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

        let points = filterGPSNoise(rawPoints, 0.15);
        const epsilon = 0.00015;
        rawPoints = simplifyPoints(points, epsilon);

        const lons = rawPoints.map(p => p.x), lats = rawPoints.map(p => p.y);
        const minLon = Math.min(...lons), maxLon = Math.max(...lons);
        const minLat = Math.min(...lats), maxLat = Math.max(...lats);

        const pointsToUse = rawPoints;

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

        let totalPathLength = 0;
        const segmentLengths = [];
        for (let i = 0; i < rawPoints.length - 1; i++) {
            const p1 = rawPoints[i];
            const p2 = rawPoints[i + 1];
            const dx = (p2.x - p1.x) * latCorrection;
            const dy = p2.y - p1.y;
            const len = Math.sqrt(dx * dx + dy * dy);
            segmentLengths.push(len);
            totalPathLength += len;
        }

        function calculatePointPosition(wpt, points, segLengths, totalLen) {
            if (totalLen === 0) return 0;
            let minDistance = Infinity;
            let currentDistSum = 0;
            let bestProgress = 0;

            for (let i = 0; i < points.length - 1; i++) {
                const p1 = points[i];
                const p2 = points[i + 1];
                const segLen = segLengths[i];

                const dx = (p2.x - p1.x) * latCorrection;
                const dy = p2.y - p1.y;
                if (segLen > 0) {
                    const u = Math.max(0, Math.min(1, ((wpt.x - p1.x) * latCorrection * dx + (wpt.y - p1.y) * dy) / (segLen * segLen)));
                    const projX = p1.x + u * (p2.x - p1.x);
                    const projY = p1.y + u * (p2.y - p1.y);
                    
                    const distToProj = Math.sqrt(((wpt.x - projX) * latCorrection) ** 2 + ((wpt.y - projY)) ** 2);
                    if (distToProj < minDistance) {
                        minDistance = distToProj;
                        bestProgress = (currentDistSum + u * segLen) / totalLen;
                    }
                }
                currentDistSum += segLen;
            }
            return Math.max(0, Math.min(100, Math.round(bestProgress * 100)));
        }

        const baseName = path.basename(fileName, path.extname(fileName)).trim();
        const projectFolder = baseName;
        fs.mkdirSync(projectFolder, { recursive: true });

        const padding = 50;
        const targetWidth = 700, targetHeight = 500;
        const lonPadding = (maxLon - minLon) * (padding / targetWidth);
        const latPadding = (maxLat - minLat) * (padding / targetHeight);

        await downloadMapImage(minLon - lonPadding, minLat - latPadding, maxLon + lonPadding, maxLat + latPadding, path.join(projectFolder, 'map.png'));

        const rmlWaypoints = [];
        const rmlAssets = [];
        let assetIdCounter = 7381110;

        for (let index = 0; index < rawWaypoints.length; index++) {
            const wpt = rawWaypoints[index];
            const wptX = Math.round(offsetX + (wpt.x - minX) * latCorrection * scale);
            const wptY = Math.round(550 - (offsetY - 50 + (wpt.y - minY) * scale));
            const pointPos = calculatePointPosition(wpt, rawPoints, segmentLengths, totalPathLength);

            // Обрабатываем картинку для текущей точки
            const imgInfo = await processWaypointImage(wpt.name, projectFolder);
            let imageAssetReferenceId = '';

            if (imgInfo) {
                const currentAssetId = assetIdCounter++;
                imageAssetReferenceId = currentAssetId;
                rmlAssets.push(`    <ImageAsset file="${imgInfo.fileName}" format="${imgInfo.format}" name="${wpt.name}" id="${currentAssetId}"/>`);
            }

            rmlWaypoints.push(`        <NestedArtboard artboardId="86:1" isStateful="true" x="${wptX}" y="${wptY}" name="${wpt.name}">
            <NestedStateMachine animationId="86:26"/>
            <ViewModelInstance viewModelId="86:11" exports="true" name="${wpt.name} Instance">
                <ViewModelInstanceString propertyValue="${wpt.name}" viewModelPropertyId="99:1"/>
                <ViewModelInstanceNumber propertyValue="${pointPos}" viewModelPropertyId="104:1"/>
                <ViewModelInstanceViewModel propertyValue="107:2" viewModelPropertyId="117:49"/>
                <ViewModelInstanceBoolean viewModelPropertyId="137:24"/>
                <ViewModelInstanceAssetImage ${imageAssetReferenceId ? `propertyValue="${imageAssetReferenceId}"` : ''} viewModelPropertyId="137:42"/>
            </ViewModelInstance>
        </NestedArtboard>`);
        }

        const yamlPath = path.join(projectFolder, 'rive.yaml');
        if (!fs.existsSync(yamlPath)) fs.writeFileSync(yamlPath, `name: ${baseName}\n`);

        const templatePath = path.join(__dirname, 'route-template.rml');
        let rmlTemplate = fs.readFileSync(templatePath, 'utf8');

        rmlTemplate = rmlTemplate
            .replace('{{RML_VERTICES}}', rmlVertices.join('\n'))
            .replace('{{RML_WAYPOINTS}}', rmlWaypoints.join('\n'))
            .replace('{{RML_ASSETS}}', rmlAssets.join('\n'));

        fs.writeFileSync(path.join(projectFolder, 'scene.rml'), rmlTemplate);
        console.log(`Проект обновлен в ${projectFolder}/`);

        try {
            execSync('rive --verify', { cwd: projectFolder, stdio: 'inherit' });
            console.log('Сборка Rive прошла успешно!');
        } catch (buildErr) {
            console.error('Ошибка сборки Rive.');
        }

        execSync('git add "../parse-route.js" "."', { cwd: path.join(__dirname, projectFolder), stdio: 'inherit' });
        execSync(`git commit -m "Generate RML with hover, scaled images and dynamic pointPosition: ${projectFolder}"`, { cwd: path.join(__dirname, projectFolder), stdio: 'inherit' });
        console.log('Готово!');

    } catch (err) {
        console.error('Ошибка:', err);
    } finally {
        rl.close();
    }
}

run();