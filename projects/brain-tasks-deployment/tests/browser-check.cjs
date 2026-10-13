// Real browser checks use isolated API fixtures. No shared or live task data is changed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { chromium } = require('playwright');

(async () => {
  const base = process.env.BROWSER_TEST_URL || 'http://127.0.0.1:3000';
  const output = path.resolve(process.env.BROWSER_TEST_OUTPUT || 'docs/screenshots');
  fs.mkdirSync(output, {recursive:true});
  const userData = fs.mkdtempSync(path.join(os.tmpdir(), 'brain-tasks-browser-'));
  const options = {
    headless:true, viewport:null, ignoreDefaultArgs:['--no-startup-window'],
    args:['--no-sandbox','--disable-dev-shm-usage','--window-size=1400,900'],
    httpCredentials:{username:process.env.BROWSER_TEST_USERNAME || 'smoke', password:process.env.BROWSER_TEST_PASSWORD || 'local-smoke-password'},
  };
  if (process.env.BROWSER_EXECUTABLE) options.executablePath=process.env.BROWSER_EXECUTABLE;
  const context = await chromium.launchPersistentContext(userData, options);
  context.setDefaultTimeout(10000);
  const errors = [];
  const page = context.pages()[0] || await context.newPage();
  const cdp=await context.newCDPSession(page);
  await cdp.send('Emulation.setDeviceMetricsOverride',{width:1400,height:900,deviceScaleFactor:1,mobile:false});
  page.on('pageerror', e => errors.push(e.message));
  let tasks = [
    {id:'1',title:'Practice Linux permissions',description:'Review chmod, chown and process troubleshooting.',completed:'Priority',createdAt:'2026-10-11T09:00:00Z'},
    {id:'2',title:'Build a Docker image',description:'Verify a nonroot container and its health endpoint.',completed:'Completed',createdAt:'2026-10-11T09:30:00Z'},
    {id:'3',title:'Prepare EKS deployment',description:'Review Deployment, Service and CloudWatch logs.',completed:'Pending',createdAt:'2026-10-11T10:00:00Z'},
  ];
  let nextId=4;
  const requests=[];
  await context.route('**/api/v1/tasks**', async route => {
    const req=route.request(), method=req.method(), pathname=new URL(req.url()).pathname;
    requests.push({method,pathname});
    const id=pathname.split('/')[4];
    if(method==='GET') {
      const body=id?tasks.find(t=>t.id===id):tasks;
      return route.fulfill({status:body?200:404,json:body || {detail:'Task not found'}});
    }
    if(method==='POST') {
      const task={...req.postDataJSON(),id:String(nextId++),createdAt:new Date().toISOString()};
      tasks.push(task);return route.fulfill({status:201,json:task});
    }
    if(method==='PUT') {
      const task=tasks.find(t=>t.id===id);Object.assign(task,req.postDataJSON());
      return route.fulfill({json:task});
    }
    if(method==='DELETE') {
      tasks=tasks.filter(t=>t.id!==id);return route.fulfill({status:204,body:''});
    }
    throw new Error('Unexpected request '+method+' '+pathname);
  });
  await context.route('https://**', route => route.abort());
  const visible = text => page.getByText(text,{exact:true}).waitFor({state:'visible'});
  try {
    console.log('Checking initial list, search and status filter');
    await page.goto(base);
    await page.getByRole('heading',{name:'Brain Tasks',exact:true}).waitFor();
    await visible('Practice Linux permissions');
    await visible('Prepare EKS deployment');
    await page.screenshot({path:path.join(output,'local-desktop.png'),fullPage:true});
    const search=page.getByPlaceholder(/Search/);
    await search.fill('Linux');
    await visible('Practice Linux permissions');
    await page.getByText('Build a Docker image',{exact:true}).waitFor({state:'hidden'});
    await search.fill('');
    await page.getByRole('button',{name:'Completed',exact:true}).click();
    await visible('Build a Docker image');
    await page.getByText('Practice Linux permissions',{exact:true}).waitFor({state:'hidden'});
    await page.getByRole('button',{name:'All Tasks',exact:true}).click();
    await page.goto(base+'/createTask');
    console.log('Checking direct create route and task creation');
    await page.getByRole('heading',{name:'Add New Task',exact:true}).waitFor();
    await page.getByLabel('Task Title').fill('Browser smoke task');
    await page.getByLabel('Description').fill('Isolated browser fixture; no live AWS data.');
    await page.screenshot({path:path.join(output,'local-create-task.png'),fullPage:true});
    await page.locator('form').getByRole('button',{name:'Create Task',exact:true}).click();
    await visible('Browser smoke task');
    assert.equal(tasks.find(t=>t.title==='Browser smoke task').id,'4');
    await page.goto(base+'/updateTask/4');
    console.log('Checking numeric edit route, update and delete');
    await page.getByRole('heading',{name:'Update Task',exact:true}).waitFor();
    await page.getByLabel('Task Title').fill('Browser smoke task updated');
    await page.locator('select').selectOption('Priority');
    // The supplied compiled edit form labels its submit button "Create Task".
    await page.locator('form button[type="submit"]').click();
    await visible('Browser smoke task updated');
    const card=page.locator('div.bg-white').filter({has:page.getByText('Browser smoke task updated',{exact:true})}).last();
    await card.locator('button').first().click();
    await card.getByText('Delete',{exact:true}).click();
    await page.getByText('Browser smoke task updated',{exact:true}).waitFor({state:'hidden'});
    assert(!tasks.some(t=>t.id==='4'));
    await cdp.send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
    await page.screenshot({path:path.join(output,'local-mobile.png'),fullPage:true});
    assert.deepEqual(errors,[]);
    const result={result:'PASS',checks:['initial task list','search','status filter','direct create route','create and refreshed list','numeric edit ID','update and refreshed list','delete','mobile render','no JavaScript page errors'],data:'isolated API fixtures',requests};
    fs.writeFileSync(path.join(output,'browser-validation.json'),JSON.stringify(result,null,2)+'\n');
    console.log(JSON.stringify(result,null,2));
  } finally {
    await context.close();
    fs.rmSync(userData,{recursive:true,force:true});
  }
})().catch(e=>{console.error(e.stack);process.exit(1)});
