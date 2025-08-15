// load_airdrop.js
// Usage: node load_airdrop.js /ruta/al/archivo.json "label_del_airdrop" [tokenAddress_0x...]

import fs from 'fs';
import { Client } from 'pg';

function hexToBuffer(hex) {
  if (!hex || typeof hex !== 'string' || !hex.startsWith('0x')) {
    throw new Error(`Hex inválido: ${hex}`);
  }
  return Buffer.from(hex.slice(2), 'hex');
}

function isHex32(hex) {
  return /^0x[0-9a-fA-F]{64}$/.test(hex);
}

function isHex20(hex) {
  return /^0x[0-9a-fA-F]{40}$/.test(hex);
}

// Construye un literal SQL ARRAY[...]::bytea[] seguro para el proof
function buildProofArrayLiteral(proofHexArray) {
  if (!Array.isArray(proofHexArray) || proofHexArray.length === 0) {
    throw new Error('proof vacío o no es arreglo');
  }
  // Validar cada hash sea 32 bytes
  const items = proofHexArray.map((h) => {
    if (!isHex32(h)) throw new Error(`Hash de proof inválido (debe ser 32 bytes): ${h}`);
    // OJO: usamos decode('...','hex') SIN el 0x
    const clean = h.slice(2);
    return `decode('${clean}','hex')`;
  });
  return `ARRAY[${items.join(', ')}]::bytea[]`;
}

async function main() {
  const [,, jsonPath, labelArg, tokenAddrArg] = process.argv;
  if (!jsonPath || !labelArg) {
    console.error('Uso: node load_airdrop.js /ruta/airdrop.json "label_del_airdrop" [tokenAddress_0x...]');
    process.exit(1);
  }

  const raw = fs.readFileSync(jsonPath, 'utf8');
  const data = JSON.parse(raw);

  // Transformar el objeto { address: entry } en un arreglo
  const entries = Object.entries(data).map(([address, entry]) => {
    if (!isHex20(address)) throw new Error(`Address inválida en key: ${address}`);
    const { inputs, proof, root, leaf, reasons } = entry;

    if (!isHex32(root)) throw new Error(`Root inválido: ${root}`);
    if (!isHex32(leaf)) throw new Error(`Leaf inválido: ${leaf}`);
    if (!Array.isArray(proof) || proof.length === 0) throw new Error(`Proof inválido para ${address}`);
    if (!Array.isArray(inputs) || inputs.length !== 2) throw new Error(`inputs inválidos para ${address}`);

    // inputs = [address, amountString]
    if (!isHex20(inputs[0])) throw new Error(`inputs[0] no es address válido: ${inputs[0]}`);
    if (inputs[0].toLowerCase() !== address.toLowerCase()) {
      throw new Error(`inputs[0] (${inputs[0]}) no coincide con key ${address}`);
    }

    // amount como string decimal (wei)
    const amountStr = String(inputs[1]);
    if (!/^\d+$/.test(amountStr)) throw new Error(`amount inválido: ${amountStr}`);

    return {
      address,
      amount: amountStr,
      proof,
      root,
      leaf,
      reasons: Array.isArray(reasons) ? reasons : [],
    };
  });

  // Validar root único
  const roots = new Set(entries.map(e => e.root.toLowerCase()));
  if (roots.size !== 1) {
    throw new Error(`Todos los entries deben compartir el mismo root. Encontrados: ${Array.from(roots).join(', ')}`);
  }
  const rootHex = entries[0].root;
  const label = labelArg;

  // Token address opcional
  let tokenAddressHex = null;
  if (tokenAddrArg) {
    if (!isHex20(tokenAddrArg)) throw new Error(`tokenAddress inválido: ${tokenAddrArg}`);
    tokenAddressHex = tokenAddrArg;
  }

  const client = new Client({
    connectionString: process.env.DATABASE_URL, // pon tu URL de Railway aquí o en env
    // ssl: { rejectUnauthorized: false }, // en Railway suele funcionar sin esto
  });

  await client.connect();

  try {
    await client.query('BEGIN');

    // Crear airdrop
    const createAirdropSql = `
      INSERT INTO airdrops (label, root, hash_fn, token_address, created_at)
      VALUES (
        $1,
        $2,                         -- bytea (root)
        'keccak256',
        $3,                         -- bytea (token_address) o null
        now()
      )
      RETURNING id;
    `;
    const airdropParams = [
      label,
      hexToBuffer(rootHex),
      tokenAddressHex ? hexToBuffer(tokenAddressHex) : null,
    ];

    const { rows } = await client.query(createAirdropSql, airdropParams);
    const airdropId = rows[0].id;

    // Insertar recipients
    for (const e of entries) {
      // Asegurar que los valores se serialicen correctamente
      const addressBuf = hexToBuffer(e.address);
      const leafBuf = hexToBuffer(e.leaf);
      const amountStr = e.amount;

      // Construir proof como arreglo de bytea (Buffers) y razones como arreglo de strings
      const proofBuffers = e.proof.map(h => hexToBuffer(h));
      const reasonsArray = e.reasons.map(r => String(r));

      const insertRecipientSql = `
        INSERT INTO airdrop_recipients
        (airdrop_id, address, amount, leaf, proof, reasons)
        VALUES (
          $1,
          $2,                -- bytea address
          $3::numeric,       -- amount
          $4,                -- bytea leaf
          $5::bytea[],       -- proof array
          $6::text[]         -- reasons array
        )
        ON CONFLICT (airdrop_id, address) DO UPDATE
        SET amount  = EXCLUDED.amount,
            leaf    = EXCLUDED.leaf,
            proof   = EXCLUDED.proof,
            reasons = EXCLUDED.reasons
      `;

      // Pasar arreglos como parámetros (Buffers y strings) en vez de interpolar literales SQL
      await client.query(insertRecipientSql, [airdropId, addressBuf, amountStr, leafBuf, proofBuffers, reasonsArray]);
    }

    await client.query('COMMIT');

    // Mostrar el último airdrop insertado (confirmación)
    const { rows: last } = await client.query(`
      SELECT id, label, '0x' || encode(root,'hex') AS root_hex, created_at
      FROM airdrops
      ORDER BY created_at DESC
      LIMIT 1;
    `);

    console.log('Airdrop creado:', last[0]);
    console.log(`Recipients insertados/actualizados: ${entries.length}`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[ERROR]', err.message);
    process.exitCode = 1;
  } finally {
    await client.end();
  }
}

main().catch((e) => {
  console.error('[FATAL]', e);
  process.exit(1);
});
