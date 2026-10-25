import { cancelRender, Composition, continueRender, delayRender, getInputProps, registerRoot, staticFile } from 'remotion';
import { CREW_MOTION, CREW_MOTION_TALL, CrewMotion } from './crew-motion';
import { DISPLAY_MOTION, DisplayMotion } from './display-motion';
import { NEEDS_YOU_MOTION, NeedsYouMotion } from './needs-you-motion';
import { REPORT_MOTION, ReportMotion } from './report-motion';

// The entry `npx remotion` renders from (testing/site.sh report, needs-you, crew and display). Geist Mono comes
// from the public folder that command makes; so does Caveat, the page's hand, for the crew alone.
const waiting = delayRender('Geist Mono');
new FontFace('Geist Mono', `url(${staticFile('GeistMono-Bold.woff2')})`, { weight: '700' })
  .load()
  .then((face) => {
    document.fonts.add(face);
    continueRender(waiting);
  }, cancelRender);
// testing/site.sh crew asks for it with `hand`; the others have no Caveat in their folder.
if (getInputProps().hand) {
  const hand = delayRender('Caveat');
  new FontFace('Caveat', `url(${staticFile('Caveat.woff2')})`, { weight: '600' })
    .load()
    .then((face) => {
      document.fonts.add(face);
      continueRender(hand);
    }, cancelRender);
}

registerRoot(() => (
  <>
    <Composition id="ReportMotion" component={ReportMotion} {...REPORT_MOTION} defaultProps={{ loop: true }} />
    <Composition id="NeedsYouMotion" component={NeedsYouMotion} {...NEEDS_YOU_MOTION} defaultProps={{ base: '' }} />
    <Composition id="CrewMotion" component={CrewMotion} {...CREW_MOTION} defaultProps={{ base: '' }} />
    <Composition id="CrewMotionTall" component={CrewMotion} {...CREW_MOTION_TALL} defaultProps={{ base: '', tall: true }} />
    <Composition id="DisplayMotion" component={DisplayMotion} {...DISPLAY_MOTION} defaultProps={{ base: '' }} />
  </>
));
