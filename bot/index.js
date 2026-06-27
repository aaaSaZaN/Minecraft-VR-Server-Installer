const mc = require('minecraft-protocol');
const mineflayer = require('mineflayer');
const { autoVersionForge } = require('minecraft-protocol-forge');
const { pathfinder, Movements, goals } = require('mineflayer-pathfinder');
const GoalNear = goals.GoalNear;
const Vec3 = require('vec3');

// Инициализация бота с поддержкой Forge рукопожатия
// version: false позволяет autoVersionForge добавить тег \0FML3\0 к хосту при handshake
const client = mc.createClient({
  host: '127.0.0.1',
  port: 25565,
  username: 'Antigravity',
  version: false
});
autoVersionForge(client);

// Перехватываем ошибки парсинга модовых пакетов на уровне клиента
// (до того как mineflayer их получит и упадёт)
client.on('error', (err) => {
  if (err && (err.field === 'play.toClient' || (err.message && err.message.includes('Read error')))) {
    console.log('[WARN] Client parse error (mod packet, non-fatal):', (err.message || '').split('\n')[0]);
    return; // поглощаем — не даём упасть
  }
  // Остальные ошибки client — пробрасываем
  console.error('[CLIENT ERROR]', err);
});

// Страховочный обработчик на уровне процесса
process.on('uncaughtException', (err) => {
  if (err && (err.field === 'play.toClient' || (err.message && (err.message.includes('unexpected tag') || err.message.includes('Read error for'))))) {
    console.log('[WARN] Suppressed uncaught parse error (mod packet):', (err.message || '').split('\n')[0]);
    return;
  }
  console.error('[UNCAUGHT]', err);
  process.exit(1);
});

const bot = mineflayer.createBot({ client });

bot.loadPlugin(pathfinder);

const GEMINI_API_KEY = process.env.GEMINI_API_KEY || "YOUR_GEMINI_API_KEY_HERE";
const MODEL_NAME = "gemini-2.5-flash";
const API_URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";

// Хранилище контекста диалогов
const conversations = {};

// Состояния бота
let isBuilding = false;
let buildQueue = [];
let currentBuildIndex = 0;

let isGathering = false;
let gatheringInterval = null;
let missingResources = {};

let isFarming = false;
let followInterval = null;

bot.on('login', () => {
  console.log('Бот успешно вошел на сервер!');
});

bot.on('spawn', () => {
  bot.chat('Привет! Я зашел на сервер в режиме выживания. Напиши мне в чат: "!agent привет" или "!agent построй деревянный дом".');
});

// Слушаем чат
bot.on('chat', async (username, message) => {
  if (username === bot.username) return;

  const msg = message.trim();
  if (msg.startsWith('!agent') || msg.startsWith('!gpt')) {
    const prompt = msg.replace(/^!(agent|gpt)\s*/i, '').trim();
    if (!prompt) return;

    bot.chat('* Думаю...');
    
    // Получаем ответ от Gemini
    const aiResponse = await callGemini(username, prompt);
    const parsed = parseAIResponse(aiResponse);
    
    // Сначала пишем ответ
    if (parsed.say) {
      bot.chat(`[Antigravity] ${parsed.say}`);
    }

    // Выполняем действия
    handleAction(parsed, username);
  }
});

// Функция вызова Gemini
async function callGemini(playerName, prompt) {
  const systemInstruction = `
You are Antigravity, a smart AI companion for players in survival Minecraft.
Your physical body is a player bot named 'Antigravity'. You do not have /op (admin rights) and must work in Survival mode.
You can help the player by:
1. Building houses (wooden or stone). Since you are in survival, you MUST ask the player for resources, pick them up, and build block-by-block.
2. Farming (planting seeds, harvesting crops).
3. Following the player or stopping.

To perform actions, you MUST return a JSON block at the end of your response using markdown syntax:
\`\`\`json
{
  "action": "build" | "farm" | "follow" | "stop" | "say",
  "style": "wood" | "stone", // only for build
  "type": "plant" | "harvest", // only for farm
  "say": "Message to show in chat"
}
\`\`\`

Rules:
1. Keep your conversational text short (1-2 sentences).
2. Ask for resources if you are going to build.
   - For a wooden house (wood), you need: 94 oak_planks, 1 oak_door, 2 glass_pane, 1 torch.
   - For a stone house (stone), you need: 94 cobblestone, 1 oak_door, 2 glass_pane, 1 torch.
   - For planting (farm/plant), you need: 1 hoe (any kind) and wheat_seeds.
3. Be friendly and helpful. Respond in the same language as the player (Russian if they speak Russian).
`;

  if (!conversations[playerName]) {
    conversations[playerName] = [];
  }
  const history = conversations[playerName];
  
  const messages = [
    { role: "system", content: systemInstruction },
    ...history.slice(-10),
    { role: "user", content: prompt }
  ];
  
  try {
    const response = await fetch(API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${GEMINI_API_KEY}`
      },
      body: JSON.stringify({
        model: MODEL_NAME,
        messages: messages,
        temperature: 0.7
      })
    });
    const data = await response.json();
    return data.choices[0].message.content;
  } catch (err) {
    console.error("Gemini API Error:", err);
    return JSON.stringify({ say: "Произошла ошибка при обращении к ИИ.", action: "say" });
  }
}

// Парсинг JSON из ответа
function parseAIResponse(reply) {
  try {
    const jsonMatch = reply.match(/```json\s*([\s\S]*?)\s*```/);
    if (jsonMatch) {
      return JSON.parse(jsonMatch[1]);
    }
    const objMatch = reply.match(/\{[\s\S]*?\}/);
    if (objMatch) {
      return JSON.parse(objMatch[0]);
    }
  } catch (err) {
    console.error("Failed to parse JSON from AI response:", err);
  }
  return { action: "say", say: reply };
}

// Обработка действий бота
function handleAction(parsed, username) {
  switch (parsed.action) {
    case 'build':
      const playerEntity = bot.players[username]?.entity;
      if (!playerEntity) {
        bot.chat('Я не вижу тебя рядом! Пожалуйста, подойди поближе.');
        return;
      }
      const buildPos = playerEntity.position.clone().add(new Vec3(3, 0, 0));
      startBuilding(parsed.style || 'wood', buildPos);
      break;

    case 'farm':
      if (parsed.type === 'harvest') {
        runHarvestingRoutine(username);
      } else {
        runPlantingRoutine(username);
      }
      break;

    case 'follow':
      startFollowing(username);
      break;

    case 'stop':
      stopAllActions();
      bot.chat('Остановился.');
      break;
  }
}

// Вспомогательная функция ходьбы
function walkTo(x, y, z, range = 1) {
  return new Promise((resolve) => {
    const defaultMove = new Movements(bot, require('minecraft-data')(bot.version));
    bot.pathfinder.setMovements(defaultMove);
    const goal = new GoalNear(x, y, z, range);
    bot.pathfinder.setGoal(goal);
    
    const onGoalReached = () => {
      cleanup();
      resolve();
    };
    
    const cleanup = () => {
      bot.off('goal_reached', onGoalReached);
    };
    
    bot.on('goal_reached', onGoalReached);
    setTimeout(() => {
      cleanup();
      resolve();
    }, 15000); // Тайм-аут 15 секунд
  });
}

// Прерывание всех действий
function stopAllActions() {
  isBuilding = false;
  stopGathering();
  stopFollowing();
  isFarming = false;
  bot.pathfinder.setGoal(null);
}

// Следование за игроком
function startFollowing(playerName) {
  stopAllActions();
  const defaultMove = new Movements(bot, require('minecraft-data')(bot.version));
  bot.pathfinder.setMovements(defaultMove);
  
  followInterval = setInterval(() => {
    const p = bot.players[playerName]?.entity;
    if (p) {
      const goal = new GoalNear(p.position.x, p.position.y, p.position.z, 2);
      bot.pathfinder.setGoal(goal);
    }
  }, 1000);
}

// Остановить следование
function stopFollowing() {
  if (followInterval) {
    clearInterval(followInterval);
    followInterval = null;
  }
}

// Логика строительства
function startBuilding(style, origin) {
  stopAllActions();
  buildQueue = generateHouseBlocks(style, origin);
  currentBuildIndex = 0;
  isBuilding = true;
  checkResourcesAndBuild();
}

function generateHouseBlocks(style, origin) {
  const blocks = [];
  const ox = Math.round(origin.x);
  const oy = Math.round(origin.y);
  const oz = Math.round(origin.z);
  
  const blockType = style === 'stone' ? 'cobblestone' : 'oak_planks';
  
  // 1. Пол (Y = oy - 1)
  for (let x = -2; x <= 2; x++) {
    for (let z = -2; z <= 2; z++) {
      blocks.push({ x: ox + x, y: oy - 1, z: oz + z, name: blockType });
    }
  }
  
  // 2. Стены (Y = oy до oy + 2)
  for (let y = 0; y <= 2; y++) {
    for (let x = -2; x <= 2; x++) {
      for (let z = -2; z <= 2; z++) {
        const isEdge = (x === -2 || x === 2 || z === -2 || z === 2);
        if (!isEdge) continue;
        
        const isWindow = (y === 1 && ((x === -2 && z === 0) || (x === 2 && z === 0)));
        const isDoor = ((y === 0 || y === 1) && (x === 0 && z === -2));
        
        if (isWindow) {
          blocks.push({ x: ox + x, y: oy + y, z: oz + z, name: 'glass_pane' });
        } else if (isDoor) {
          if (y === 0) {
            blocks.push({ x: ox + x, y: oy + y, z: oz + z, name: 'oak_door' });
          }
        } else {
          blocks.push({ x: ox + x, y: oy + y, z: oz + z, name: blockType });
        }
      }
    }
  }
  
  // 3. Крыша (Y = oy + 3)
  for (let x = -2; x <= 2; x++) {
    for (let z = -2; z <= 2; z++) {
      blocks.push({ x: ox + x, y: oy + 3, z: oz + z, name: blockType });
    }
  }
  
  // 4. Освещение
  blocks.push({ x: ox, y: oy + 1, z: oz, name: 'torch' });
  
  return blocks;
}

function getRequiredResources(queue) {
  const req = {};
  for (const b of queue) {
    req[b.name] = (req[b.name] || 0) + 1;
  }
  return req;
}

function checkResourcesAndBuild() {
  if (!isBuilding) return;
  
  const req = getRequiredResources(buildQueue.slice(currentBuildIndex));
  const missing = {};
  let anyMissing = false;
  
  for (const [name, count] of Object.entries(req)) {
    const invCount = getItemCount(name);
    if (invCount < count) {
      missing[name] = count - invCount;
      anyMissing = true;
    }
  }
  
  if (anyMissing) {
    missingResources = missing;
    const reqStr = Object.entries(missing).map(([name, count]) => `${count}x ${name}`).join(', ');
    bot.chat(`[Antigravity] Мне не хватает ресурсов для стройки: ${reqStr}. Сбросьте их мне под ноги!`);
    startGathering();
  } else {
    missingResources = {};
    bot.chat("[Antigravity] Все ресурсы собраны! Начинаю возведение.");
    executeBuildQueue();
  }
}

function getItemCount(name) {
  const mcData = require('minecraft-data')(bot.version);
  const itemInfo = mcData.itemsByName[name];
  if (!itemInfo) return 0;
  return bot.inventory.count(itemInfo.id);
}

// Логика сбора ресурсов
function startGathering() {
  if (isGathering) return;
  isGathering = true;
  
  gatheringInterval = setInterval(async () => {
    if (!isGathering) return;
    
    // Ищем дропнутые предметы в радиусе 15 блоков
    const droppedItem = bot.nearestEntity(e => {
      return e.name === 'item' && bot.entity.position.distanceTo(e.position) < 15;
    });
    
    if (droppedItem) {
      console.log(`Вижу предмет на ${droppedItem.position}, иду подбирать.`);
      try {
        await walkTo(droppedItem.position.x, droppedItem.position.y, droppedItem.position.z, 0.5);
      } catch (err) {
        console.log("Ошибка ходьбы к предмету:", err);
      }
    } else {
      // Раз в пару секунд пересчитываем инвентарь
      const stillMissing = {};
      let anyMissing = false;
      const req = getRequiredResources(buildQueue.slice(currentBuildIndex));
      
      for (const [name, count] of Object.entries(req)) {
        const invCount = getItemCount(name);
        if (invCount < count) {
          stillMissing[name] = count - invCount;
          anyMissing = true;
        }
      }
      
      if (!anyMissing) {
        stopGathering();
        checkResourcesAndBuild();
      }
    }
  }, 1500);
}

function stopGathering() {
  isGathering = false;
  if (gatheringInterval) {
    clearInterval(gatheringInterval);
    gatheringInterval = null;
  }
}

// Пошаговое укладывание блоков
async function executeBuildQueue() {
  stopGathering();
  
  while (currentBuildIndex < buildQueue.length) {
    if (!isBuilding) return;
    
    const target = buildQueue[currentBuildIndex];
    const targetPos = new Vec3(target.x, target.y, target.z);
    
    // Проверяем, не стоит ли уже этот блок
    const currentBlock = bot.blockAt(targetPos);
    if (currentBlock && currentBlock.name === target.name) {
      currentBuildIndex++;
      continue;
    }
    
    // Проверяем наличие в инвентаре
    const mcData = require('minecraft-data')(bot.version);
    const itemInfo = mcData.itemsByName[target.name];
    const item = bot.inventory.items().find(i => i.type === itemInfo.id);
    
    if (!item) {
      checkResourcesAndBuild();
      return;
    }
    
    // Подходим поближе
    const dist = bot.entity.position.distanceTo(targetPos);
    if (dist > 4) {
      await walkTo(target.x, target.y, target.z, 3);
    }
    
    try {
      await bot.equip(item, 'hand');
      
      // Ищем соседний твердый блок для клика
      const adjacentDirs = [
        new Vec3(0, -1, 0),
        new Vec3(0, 1, 0),
        new Vec3(-1, 0, 0),
        new Vec3(1, 0, 0),
        new Vec3(0, 0, -1),
        new Vec3(0, 0, 1)
      ];
      
      let refBlock = null;
      let faceVector = null;
      
      for (const dir of adjacentDirs) {
        const checkPos = targetPos.plus(dir);
        const block = bot.blockAt(checkPos);
        if (block && block.name !== 'air' && block.name !== 'water' && block.name !== 'lava') {
          refBlock = block;
          faceVector = dir.scaled(-1);
          break;
        }
      }
      
      if (refBlock) {
        await bot.placeBlock(refBlock, faceVector);
      } else {
        console.log(`Нет опоры для ${target.name} на ${target.x}, ${target.y}, ${target.z}`);
      }
    } catch (err) {
      console.log(`Ошибка установки блока ${target.name}:`, err.message);
    }
    
    currentBuildIndex++;
    await new Promise(r => setTimeout(r, 150)); // задержка 150 мс для реализма
  }
  
  bot.chat("[Antigravity] Я закончил строительство дома!");
  isBuilding = false;
}

// Логика фермерства: вспахивание и посадка
async function runPlantingRoutine(playerName) {
  stopAllActions();
  isFarming = true;
  
  const hoe = bot.inventory.items().find(i => i.name.endsWith('hoe'));
  const seeds = bot.inventory.items().find(i => i.name === 'wheat_seeds');
  
  if (!hoe || !seeds) {
    bot.chat("[Antigravity] Мне нужна мотыга (hoe) и семена пшеницы (wheat_seeds)!");
    isFarming = false;
    return;
  }
  
  bot.chat("[Antigravity] Ищу воду для грядки...");
  const waterPositions = bot.findBlocks({
    matching: block => block.name === 'water',
    maxDistance: 15,
    count: 1
  });
  
  if (waterPositions.length === 0) {
    bot.chat("[Antigravity] Не вижу воды поблизости! Сделайте лужицу воды.");
    isFarming = false;
    return;
  }
  
  const waterPos = waterPositions[0];
  const adjacentCoords = [
    new Vec3(1, 0, 0), new Vec3(-1, 0, 0),
    new Vec3(0, 0, 1), new Vec3(0, 0, -1),
    new Vec3(1, 0, 1), new Vec3(-1, 0, 1),
    new Vec3(1, 0, -1), new Vec3(-1, 0, -1)
  ];
  
  let targetFarmlandPos = null;
  for (const offset of adjacentCoords) {
    const checkPos = waterPos.plus(offset);
    const block = bot.blockAt(checkPos);
    const blockAbove = bot.blockAt(checkPos.up(1));
    if (block && (block.name === 'grass_block' || block.name === 'dirt') && blockAbove && blockAbove.name === 'air') {
      targetFarmlandPos = checkPos;
      break;
    }
  }
  
  if (!targetFarmlandPos) {
    bot.chat("[Antigravity] Земля у воды занята или отсутствует.");
    isFarming = false;
    return;
  }
  
  await walkTo(targetFarmlandPos.x, targetFarmlandPos.y + 1, targetFarmlandPos.z, 2);
  
  try {
    await bot.equip(hoe, 'hand');
    const blockToTill = bot.blockAt(targetFarmlandPos);
    await bot.activateBlock(blockToTill, new Vec3(0, 1, 0));
    await new Promise(r => setTimeout(r, 300));
    
    const freshSeeds = bot.inventory.items().find(i => i.name === 'wheat_seeds');
    if (freshSeeds) {
      await bot.equip(freshSeeds, 'hand');
      const farmlandBlock = bot.blockAt(targetFarmlandPos);
      await bot.placeBlock(farmlandBlock, new Vec3(0, 1, 0));
      bot.chat("[Antigravity] Вспахал грядку и посадил семена!");
    }
  } catch (err) {
    console.log("Farm planting error:", err);
    bot.chat("[Antigravity] Не удалось завершить посадку.");
  }
  
  isFarming = false;
}

// Логика фермерства: сбор урожая
async function runHarvestingRoutine(playerName) {
  stopAllActions();
  isFarming = true;
  
  const ripeWheatPositions = bot.findBlocks({
    matching: block => block.name === 'wheat' && block.metadata === 7,
    maxDistance: 15,
    count: 5
  });
  
  if (ripeWheatPositions.length === 0) {
    bot.chat("[Antigravity] Не нашел полностью созревшей пшеницы.");
    isFarming = false;
    return;
  }
  
  bot.chat(`[Antigravity] Собираю пшеницу (${ripeWheatPositions.length} шт.).`);
  
  for (const pos of ripeWheatPositions) {
    if (!isFarming) return;
    try {
      await walkTo(pos.x, pos.y, pos.z, 2);
      const block = bot.blockAt(pos);
      await bot.dig(block);
      await new Promise(r => setTimeout(r, 600)); // ждем подбора дропа
      
      const seeds = bot.inventory.items().find(i => i.name === 'wheat_seeds');
      if (seeds) {
        await bot.equip(seeds, 'hand');
        const farmland = bot.blockAt(pos.down(1));
        if (farmland && farmland.name === 'farmland') {
          await bot.placeBlock(farmland, new Vec3(0, 1, 0));
        }
      }
    } catch (err) {
      console.log("Harvest error:", err);
    }
  }
  
  bot.chat("[Antigravity] Урожай собран! Иду отдавать.");
  const player = bot.players[playerName]?.entity;
  if (player) {
    await walkTo(player.position.x, player.position.y, player.position.z, 2);
    const wheatItem = bot.inventory.items().find(i => i.name === 'wheat');
    if (wheatItem) {
      await bot.tossStack(wheatItem);
      bot.chat("[Antigravity] Вот пшеница!");
    }
  }
  
  isFarming = false;
}

bot.on('error', (err) => {
  // Ошибки парсинга модовых пакетов — некритичны
  if (err && (err.field === 'play.toClient' || (err.message && (err.message.includes('unexpected tag') || err.message.includes('Read error'))))) {
    console.log('[WARN] Bot error (mod packet, non-fatal):', (err.message || '').split('\n')[0]);
    return;
  }
  console.log('Критическая ошибка бота: ', err);
});

bot.on('end', () => {
  console.log('Бот отключился от сервера. Перезапуск через 5 секунд...');
  setTimeout(() => {
    process.exit(1);
  }, 5000);
});
