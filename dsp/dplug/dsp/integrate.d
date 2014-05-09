module dplug.dsp.integrate;

// Fixed time-step integration.


/**
* Test for the Integrator concept.
*
* An integrator has the following features:
* $(UL
* $(LI defines state_t.)
* $(LI defines derivative_t.)
* $(LI defines the integrate function.)
* )
*/
template isIntegrator(I)
{
    enum bool isIntegrator = is(typeof(
    {
        alias state_t = I.state_t;
        alias derivative_t = I.derivative_t;
        I integr;
        state_t s;                      // can be defined
        derivative_t d;
        double t, dt;
        s = s + d * dt;
        derivative_t delegate(state_t input) evaluate;
        state_t newState = integr.integrate(s, dt, evaluate);
    }()));
}

// Explicit euler integrator.
struct ExplicitEuler(State)
{
    alias state_t = State;
    alias derivative_t = State;

    State integrate(State current, double dt, derivative_t delegate(State input) evaluate)
    {
        return current + dt * integrate(current);
    }
}

// Runge-Kutta order 2 integrator.
struct RungeKutta2(State)
{
    alias state_t = State;
    alias derivative_t = State;

    State integrate(State current, double dt, derivative_t delegate(State input) evaluate)
    {
        derivative_t a = evaluate(current);
        derivative_t b = evaluate(current + (dt * 0.5) * a);
        derivative_t filteredDerivative = (a + b) / 2;
        return current + dt * filteredDerivative;
    }
}


// Runge-Kutta order 4 integrator.
struct RungeKutta4(State)
{
    alias state_t = State;
    alias derivative_t = State;

    State integrate(State current, double dt, derivative_t delegate(State input) evaluate)
    {
        derivative_t a = evaluate(current);
        derivative_t b = evaluate(current + (dt * 0.5) * a);
        derivative_t c = evaluate(current + (dt * 0.5) * b);
        derivative_t d = evaluate(current + dt * c);
        derivative_t filteredDerivative = ( a + 2 * (b + c) + d ) / 6;
        return current + dt * filteredDerivative;
    }
}


static assert(isIntegrator!(RungeKutta4!float));
