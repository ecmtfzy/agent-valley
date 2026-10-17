import { cancelRender, Composition, continueRender, delayRender, registerRoot, staticFile } from 'remotion';
import { REPORT_MOTION, ReportMotion } from './report-motion';

// The entry `npx remotion` renders from (testing/site.sh report). The site loads Geist Mono
// itself; here it comes from the public folder that command makes.
const waiting = delayRender('Geist Mono');
new FontFace('Geist Mono', `url(${staticFile('GeistMono-Bold.woff2')})`, { weight: '700' })
  .load()
  .then((face) => {
    document.fonts.add(face);
    continueRender(waiting);
  }, cancelRender);

registerRoot(() => <Composition id="ReportMotion" component={ReportMotion} {...REPORT_MOTION} defaultProps={{ loop: true, base: '' }} />);
