import uuid

PASSWORD = 'Phase2-strong-password-42'
def register(client, email):
    r = client.post('/api/v1/auth/register', json={'email': email, 'password': PASSWORD})
    assert r.status_code == 201, r.text
    return {'Authorization': 'Bearer ' + r.json()['access_token']}
def plot(client, h, name='North', area=2.5):
    r=client.post('/api/v1/plots', headers=h, json={'name':name,'area':area,'soil':'loam'})
    assert r.status_code==201, r.text
    return r.json()
def cycle_body(plot_id, **extra):
    return {'name':'Rice 1','plotId':plot_id,'cropType':'rice','variety':'พื้นเมือง','plantingMethod':'direct','startDate':'2026-09-01',**extra}
def activity_body(cycle_id, **extra):
    return {'cycleId':cycle_id,'type':'fertilize','date':'2026-09-05','description':'field work',**extra}

def test_phase2_two_farmer_isolation_and_full_crud(client):
    a=register(client,'a-phase2@example.com'); b=register(client,'b-phase2@example.com')
    p=plot(client,a); pb=plot(client,b,'South',3)
    assert [x['id'] for x in client.get('/api/v1/plots',headers=a).json()]==[p['id']]
    assert client.get('/api/v1/plots/'+p['id'],headers=b).status_code==404
    assert client.patch('/api/v1/plots/'+p['id'],headers=a,json={'name':'North updated'}).status_code==200
    assert client.delete('/api/v1/plots/'+pb['id'],headers=b).status_code==204
    assert client.get('/api/v1/plots/'+pb['id'],headers=b).status_code==404
    c=client.post('/api/v1/cycles',headers=a,json=cycle_body(p['id'])).json()
    assert c['plotName']=='North updated'
    assert client.get('/api/v1/cycles',headers=b).json()==[]
    act=client.post('/api/v1/activities',headers=a,json=activity_body(c['id'])).json()
    assert client.get('/api/v1/activities/'+act['id'],headers=b).status_code==404
    assert client.patch('/api/v1/activities/'+act['id'],headers=a,json={'description':'updated'}).status_code==200
    assert client.delete('/api/v1/activities/'+act['id'],headers=a).status_code==204
    assert client.delete('/api/v1/cycles/'+c['id'],headers=a).status_code==204
    assert client.delete('/api/v1/plots/'+p['id'],headers=a).status_code==204

def test_phase2_foreign_parent_ids_and_delete_conflicts(client):
    a=register(client,'a-parent@example.com'); b=register(client,'b-parent@example.com')
    pa=plot(client,a); pb=plot(client,b)
    assert client.post('/api/v1/cycles',headers=a,json=cycle_body(pb['id'])).status_code==404
    ca=client.post('/api/v1/cycles',headers=a,json=cycle_body(pa['id'])).json()
    assert client.post('/api/v1/activities',headers=b,json=activity_body(ca['id'])).status_code==404
    ac=client.post('/api/v1/activities',headers=a,json=activity_body(ca['id'])).json()
    assert client.delete('/api/v1/plots/'+pa['id'],headers=a).status_code==409
    assert client.delete('/api/v1/cycles/'+ca['id'],headers=a).status_code==409
    assert client.patch('/api/v1/cycles/'+ca['id'],headers=a,json={'plotId':pb['id']}).status_code==404
    assert client.patch('/api/v1/activities/'+ac['id'],headers=a,json={'cycleId':str(uuid.uuid4())}).status_code==404

def test_phase2_harvest_closes_cycle_and_rejects_later_activity_writes(client):
    h=register(client,'harvest-phase2@example.com'); p=plot(client,h); c=client.post('/api/v1/cycles',headers=h,json=cycle_body(p['id'])).json()
    r=client.post('/api/v1/activities',headers=h,json=activity_body(c['id'],type='harvest',completeCycle=True))
    assert r.status_code==201; assert client.get('/api/v1/cycles/'+c['id'],headers=h).json()['status']=='completed'
    assert client.post('/api/v1/activities',headers=h,json=activity_body(c['id'])).status_code==409
    assert client.patch('/api/v1/activities/'+r.json()['id'],headers=h,json={'description':'x'}).status_code==409
    assert client.delete('/api/v1/activities/'+r.json()['id'],headers=h).status_code==409
    assert client.patch('/api/v1/cycles/'+c['id'],headers=h,json={'status':'active'}).status_code==200

def test_phase2_malformed_optional_fields_are_422(client):
    h=register(client,'validation-phase2@example.com'); p=plot(client,h)
    assert client.post('/api/v1/plots',headers=h,json={'name':'bad','area':'not-number'}).status_code==422
    assert client.post('/api/v1/cycles',headers=h,json=cycle_body(p['id'],startDate='2026-99-99')).status_code==422
    assert client.post('/api/v1/activities',headers=h,json=activity_body(str(uuid.uuid4()),description=12)).status_code==422
    assert client.post('/api/v1/plots',headers=h,json={'name':'bad','area':1,'ownerUserId':str(uuid.uuid4())}).status_code==422
