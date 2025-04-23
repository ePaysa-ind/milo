const admin = require('firebase-admin');
const fs = require('fs');

console.log('Script started...');

try {
  console.log('Reading service account file...');
  const rawData = fs.readFileSync('C:/Users/raman/AndroidStudioProjects/Milo/scripts/serviceAccountKey.json', 'utf8');
  console.log('File read successfully. First 20 characters:', rawData.substring(0, 20));

  try {
    console.log('Parsing JSON...');
    const serviceAccount = JSON.parse(rawData);
    console.log('JSON parsed successfully. Found these keys:', Object.keys(serviceAccount).join(', '));

    console.log('Initializing Firebase app...');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('Firebase initialized successfully!');

    const db = admin.firestore();
    console.log('Firestore database initialized!');

    // Read the templates JSON file
    try {
      console.log('Reading templates file...');
      const templatesData = fs.readFileSync('./improved_nudge_templates.json', 'utf8');
      console.log('Templates file read successfully!');

      try {
        console.log('Parsing templates JSON...');
        const templates = JSON.parse(templatesData);
        console.log(`Successfully parsed ${templates.length} templates from file`);

        // Import templates in batches (Firestore has a limit of 500 operations per batch)
        async function importTemplates() {
          const batchSize = 400; // Firestore limit is 500, using 400 to be safe
          let totalImported = 0;

          // Process templates in batches
          for (let i = 0; i < templates.length; i += batchSize) {
            const batch = db.batch();
            const currentBatch = templates.slice(i, i + batchSize);

            console.log(`Processing batch of ${currentBatch.length} templates...`);

            // Add each template to the batch
            currentBatch.forEach(template => {
              const docRef = db.collection('nudgeTemplates').doc(template.id);
              batch.set(docRef, template);
            });

            try {
              // Commit the batch
              console.log('Committing batch to Firestore...');
              await batch.commit();
              totalImported += currentBatch.length;
              console.log(`Imported ${totalImported}/${templates.length} templates`);
            } catch (batchError) {
              console.error('Error committing batch to Firestore:', batchError);
              throw batchError;
            }
          }

          console.log('Import completed successfully!');
        }

        // Run the import
        importTemplates()
          .then(() => {
            console.log('All templates imported. You can now check your Firestore database.');
            process.exit(0);
          })
          .catch(error => {
            console.error('Error during import process:', error);
            process.exit(1);
          });

      } catch (templatesJsonError) {
        console.error('Error parsing templates JSON:', templatesJsonError);
        console.log('First 100 characters of templates file:', templatesData.substring(0, 100));
        process.exit(1);
      }
    } catch (templatesFileError) {
      console.error('Error reading templates file:', templatesFileError);
      process.exit(1);
    }
  } catch (jsonError) {
    console.error('Error parsing service account JSON:', jsonError);
    console.log('First 100 characters of service account file:', rawData.substring(0, 100));
    process.exit(1);
  }
} catch (fileError) {
  console.error('Error reading service account file:', fileError);
  process.exit(1);
}