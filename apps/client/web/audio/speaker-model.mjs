const modelHash = '9fea6516d7ad6bf0a76c7689f5a49b65d330fad6dde96c91bb4435ffbfe056a1';
const parts = [
  {size:13267064,hash:'5f13c76053904da95d8c4019d0daa4b46fc264e617f8cf2e900cf84da740eadc'},
  {size:13267063,hash:'04df71456b0571247284f97e13680ca2f642617af0e6cf0d8658094e2432b342'},
];

export async function loadSpeakerModel({fetchPart,digest,create}) {
  const fetched = []; let model;
  const hash = async bytes => Array.from(new Uint8Array(await digest(bytes)),value=>value.toString(16).padStart(2,'0')).join('');
  try {
    for (let index=0;index<parts.length;index++) {
      const response=await fetchPart(index);
      if (!response.ok) throw Error('Model HTTP failure');
      const bytes=new Uint8Array(await response.arrayBuffer());fetched.push(bytes);
      if (bytes.length!==parts[index].size || await hash(bytes)!==parts[index].hash) throw Error('Model part mismatch');
    }
    model=new Uint8Array(parts[0].size+parts[1].size);
    model.set(fetched[0]);model.set(fetched[1],parts[0].size);
    if (await hash(model)!==modelHash) throw Error('Model hash mismatch');
    return await create(model.buffer);
  } finally { for(const bytes of fetched)bytes.fill(0);model?.fill(0); }
}
