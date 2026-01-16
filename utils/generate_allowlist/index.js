import fs from 'fs';
import path from 'path';
import csv from 'csv-parser';

const TOKEN_AMOUNT = BigInt('1000000000000000000'); // 1 * 10^18

/**
 * Genera el objeto con la información de cada fila a partir del CSV actualizado.
 * - Toma el total ya calculado de la columna "Rewards".
 * - Genera las razones usando badge_17_tier (Self Verification),
 *   badge_22_tier (S1 Transactions) y badge_26_tier (Celo Vault Deposit).
 * @param {Object} row - Fila parseada del CSV.
 */
function createEntry(row) {
  const address = (row['account'] || '').trim();

  // Parseo de columnas relevantes para reasons
  const badge17Tier = parseInt(row['badge_17_tier'], 10) || 0;
  const badge22Tier = parseInt(row['badge_22_tier'], 10) || 0;
  const badge26Tier = parseInt(row['badge_26_tier'], 10) || 0;
  const ppLevel = parseInt(row['pp_level'], 10) || 0;

  // Total de recompensa pre-calculado (en unidades enteras de token)
  // Convertimos a wei multiplicando por 1e18
  const rawReward = (row['Rewards'] || '0').toString().replace(/,/g, '').trim();
  const rewardTokens = BigInt(rawReward || '0') * TOKEN_AMOUNT;

  // Construcción de reasons
  const reasons = [];
  if (badge17Tier > 0) reasons.push(`Self verification - Tier ${badge17Tier}`);
  if (badge22Tier > 0) reasons.push(`S1 Transactions - Tier ${badge22Tier}`);
  if (badge26Tier > 0) reasons.push(`Celo Vault Deposit - Tier ${badge26Tier}`);
  if (ppLevel > 0) reasons.push(`Prosperity Passport - Level ${ppLevel}`);

  return {
    address,
    tokenAmount: rewardTokens.toString(),
    reasons,
  };
}

/**
 * Lee un CSV y construye un JSON con la estructura solicitada:
 * {
 *   "types": ["address", "uint"],
 *   "count": <N>,
 *   "values": {
 *       "0": {"0": <address>, "1": <token>, "reasons": [<razones>]},
 *       ...
 *   }
 * }
 */
function generateAllowlist() {
  const csvPath = './allowlist.csv';
  const outputPath = './allowlist.json';
  const entries = [];
  let rowCount = 0;

  fs.createReadStream(path.resolve(csvPath))
    .pipe(csv())
    .on('data', (row) => {
      if (rowCount === 0) {
        console.log('First row keys:', Object.keys(row));
      }
      rowCount++;
      const entry = createEntry(row);
      if (entry.address) {
        entries.push(entry);
      }
    })
    .on('end', () => {
      console.log(
        `Total rows processed: ${rowCount}, Valid entries: ${entries.length}`
      );

      const finalOutput = {
        types: ['address', 'uint'],
        count: entries.length,
        values: {},
      };

      entries.forEach((item, index) => {
        finalOutput.values[index] = {
          0: item.address,
          1: item.tokenAmount,
          reasons: item.reasons,
        };
      });

      const jsonOutput = JSON.stringify(finalOutput, null, 2);

      if (outputPath) {
        fs.writeFileSync(path.resolve(outputPath), jsonOutput, 'utf8');
        console.log(`Archivo JSON generado en: ${outputPath}`);
      } else {
        console.log(jsonOutput);
      }
    });
}

generateAllowlist();
