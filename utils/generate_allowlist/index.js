import fs from 'fs';
import path from 'path';
import csv from 'csv-parser';

const TOKEN_AMOUNT = BigInt('1000000000000000000'); // 1 * 10^18

/**
 * Genera el objeto con la información de cada fila a partir del CSV actualizado.
 * - Toma el total ya calculado de la columna "S0 Reward".
 * - Genera las razones usando "Prosperity Pass Level", "Self Verified" y "S0 Gov Contributor".
 * @param {Object} row - Fila parseada del CSV.
 */
function createEntry(row) {
  const address = (row['PP Address'] || '').trim();

  // Parseo de columnas relevantes para reasons
  const level = parseInt(row['Prosperity Pass Level'], 10) || 0;
  const selfVerified =
    String(row['Self Verified'] || '')
      .trim()
      .toLowerCase() === 'yes';
  const govContributor = parseInt(row['S0 Gov Contributor'], 10) || 0;

  // Total de recompensa pre-calculado (en unidades enteras de token, e.g. "2,750")
  // Convertimos a wei multiplicando por 1e18
  const rawReward = (row['S0 Reward'] || '0').toString().replace(/,/g, '').trim();
  const rewardTokens = BigInt(rawReward || '0') * TOKEN_AMOUNT;

  // Construcción de reasons
  const reasons = [];
  if (level > 0) reasons.push(`Reached level ${level}`);
  if (selfVerified) reasons.push('Self Verified');
  if (govContributor > 0) reasons.push(`S0 Gov Contributor Tier ${govContributor}`);

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

  fs.createReadStream(path.resolve(csvPath))
    .pipe(csv())
    .on('data', (row) => {
      const entry = createEntry(row);
      entries.push(entry);
    })
    .on('end', () => {
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
