const modelHash = '9fea6516d7ad6bf0a76c7689f5a49b65d330fad6dde96c91bb4435ffbfe056a1';

export async function loadSpeakerModel({fetchModel,digest,create}) {
  const response = await fetchModel();
  if (!response.ok) throw Error('Model HTTP failure');
  const bytes = await response.arrayBuffer();
  const hash = Array.from(new Uint8Array(await digest(bytes)), value=>value.toString(16).padStart(2,'0')).join('');
  if (hash !== modelHash) throw Error('Model hash mismatch');
  return create(bytes);
}
