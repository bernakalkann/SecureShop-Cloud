const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');

// AWS RDS Bilgileri
const dbConfig = {
  host: process.env.DB_HOST || 'secureshop-db.c69ogseskkfq.us-east-1.rds.amazonaws.com',
  user: process.env.DB_USER || 'admin',
  password: process.env.DB_PASSWORD || '27Antep27',
  port: parseInt(process.env.DB_PORT, 10) || 3306
};

async function initializeDatabase() {
  console.log("=== AWS RDS MYSQL BAĞLANTI VE KURULUM SÜRECİ ===");
  console.log(`Sunucu: ${dbConfig.host}`);
  console.log("Bağlantı kuruluyor...");
  
  let connection;
  try {
    // Veritabanı adı belirtmeden bağlan
    connection = await mysql.createConnection(dbConfig);
    console.log("[✓] AWS RDS MySQL sunucusuna başarıyla bağlanıldı.");
    
    // schema.sql dosyasını oku
    const schemaPath = path.join(__dirname, 'aws', 'schema.sql');
    if (!fs.existsSync(schemaPath)) {
      throw new Error(`schema.sql bulunamadı: ${schemaPath}`);
    }
    
    console.log("schema.sql okunuyor...");
    const rawSql = fs.readFileSync(schemaPath, 'utf8');
    
    // SQL satırlarını temizle (Hem satır yorumlarını hem de satır içi -- yorumlarını temizler)
    const sqlStatements = rawSql
      .split('\n')
      .map(line => {
        // Satırdaki ilk -- veya # işaretinden sonrasını kesip atar (Yorumları temizler)
        let cleanLine = line.split('--')[0].split('#')[0];
        return cleanLine.trim();
      })
      .filter(line => line.length > 0)
      .join(' ')
      .split(';');
      
    console.log(`Toplam ${sqlStatements.length} SQL ifadesi çalıştırılacak.`);
    
    for (let statement of sqlStatements) {
      statement = statement.trim();
      if (!statement) continue;
      
      // SQL deyimini çalıştır
      try {
        await connection.query(statement);
        if (statement.startsWith('CREATE DATABASE')) {
          console.log("[+] Veritabanı başarıyla oluşturuldu/doğrulandı.");
        } else if (statement.startsWith('CREATE TABLE')) {
          const tableName = statement.match(/CREATE TABLE (\w+)/i)[1];
          console.log(`[+] Tablo oluşturuldu: ${tableName}`);
        } else if (statement.startsWith('INSERT INTO')) {
          const tableName = statement.match(/INSERT INTO (\w+)/i)[1];
          console.log(`[+] Veriler eklendi: ${tableName}`);
        } else if (statement.startsWith('USE')) {
          console.log(`[+] Aktif Veritabanı seçildi.`);
        }
      } catch (err) {
        if (err.code === 'ER_TABLE_EXISTS_ERROR' || err.code === 'ER_DB_CREATE_EXISTS') {
          console.log(`[!] ${err.message} (Gözardı edildi)`);
        } else {
          console.error(`[-] SQL Çalıştırılırken Hata: ${err.message}`);
          console.error(`Hatalı Sorgu: ${statement}`);
          throw err;
        }
      }
    }
    
    console.log("\n[✓] AWS RDS VERİTABANI BAŞARIYLA BAŞLATILDI VE DOLDURULDU!");
    
  } catch (error) {
    console.error("\n[✗] Kurulum Hatası:", error.message);
  } finally {
    if (connection) {
      await connection.end();
      console.log("Bağlantı kapatıldı.");
    }
  }
}

initializeDatabase();
