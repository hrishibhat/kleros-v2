import React from "react";
import styled from "styled-components";
import { Tabs, Card } from "@kleros/ui-components-library";
import { useLocalStorage } from "hooks/useLocalStorage";
import { tabItems, pages } from "./tabs";
import Notifications from "components/notifications";

const Wrapper = styled.div`
  width: 70vw;
  height: 70vh;
`;

const StyledTabs = styled(Tabs)`
  position: relative;
  top: 1px;
  width: 100%;
`;

const StyledCard = styled(Card)`
  height: 100%;
  width: 100%;
`;

const Main = () => {
  const [current, setCurrent] = useLocalStorage("tabIndex", 0);
  const Page = pages[current];
  return (
    <Wrapper>
      <Notifications />
      <StyledTabs
        items={tabItems}
        callback={(value: number) => {
          setCurrent(value);
        }}
        currentValue={current}
      />
      <StyledCard>
        <Page />
      </StyledCard>
    </Wrapper>
  );
};

export default Main;
